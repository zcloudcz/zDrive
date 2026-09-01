using ZDrive.BackupCli.Api;

namespace ZDrive.BackupCli.Backup;

/// <summary>
/// Recursively mirrors a local directory into zDrive.
///
/// Idempotence/resumability strategy (deliberately simple — no local state
/// file, see docs/release-test-deploy.md "Agent 4"): on every run, list the
/// remote folder's children and, for files that already have a node, fetch
/// their upload manifest. A file is skipped only when a manifest exists,
/// its chunk hashes match the local file exactly, AND FileService has a
/// version recorded for that exact content; otherwise the whole file is
/// (re-)uploaded. A node with no manifest means a previous run created the
/// file entry but never finished the upload (e.g. was killed mid-way) —
/// re-uploading it here is what makes an interrupted run resumable. A
/// matching manifest with no FileService version means the upload itself
/// finished but the run died before recording the version — that gets
/// repaired by recording the version, without re-uploading the content.
/// </summary>
public sealed class BackupRunner(IZdriveApiClient api, TextWriter stdout, TextWriter stderr)
{
    public async Task<int> RunAsync(string localRoot, string? destPath, CancellationToken ct)
    {
        var rootId = await ResolveDestPathAsync(destPath, ct);
        var stats = new Stats();
        await BackupDirectoryAsync(new DirectoryInfo(localRoot), rootId, stats, ct);

        stdout.WriteLine($"Backup finished: {stats.Uploaded} uploaded, {stats.Skipped} skipped, {stats.Failed} failed.");
        return stats.Failed == 0 ? 0 : 1;
    }

    /// <summary>Ensures the "--dest" folder path exists remotely, creating segments as needed.</summary>
    private async Task<Guid?> ResolveDestPathAsync(string? destPath, CancellationToken ct)
    {
        Guid? parentId = null;
        if (string.IsNullOrWhiteSpace(destPath))
            return parentId;

        foreach (var segment in destPath.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            var children = await api.ListChildrenAsync(parentId, ct);
            parentId = children.TryGetValue(segment, out var existing) && existing.IsFolder
                ? existing.Id
                : (await api.CreateFolderAsync(parentId, segment, ct)).Id;
        }
        return parentId;
    }

    private async Task BackupDirectoryAsync(DirectoryInfo dir, Guid? remoteParentId, Stats stats, CancellationToken ct)
    {
        // Listing/enumeration is one unit of work: if it fails (remote API
        // hiccup, or the directory itself becomes unreadable mid-enumeration),
        // that's a failure of this one directory, not the whole run — record
        // it and let the caller move on to sibling directories/files.
        IReadOnlyDictionary<string, FileNode> existing;
        List<DirectoryInfo> subDirs;
        List<FileInfo> files;
        try
        {
            existing = await api.ListChildrenAsync(remoteParentId, ct);
            subDirs = dir.EnumerateDirectories().OrderBy(d => d.Name, StringComparer.Ordinal).ToList();
            files = dir.EnumerateFiles().OrderBy(f => f.Name, StringComparer.Ordinal).ToList();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            stats.Failed++;
            stderr.WriteLine($"ERROR  {dir.FullName}: {ex.Message}");
            return;
        }

        foreach (var subDir in subDirs)
        {
            ct.ThrowIfCancellationRequested();

            try
            {
                // Symlinked directories could point outside the backup root or
                // back at an ancestor (infinite recursion) — skip them rather
                // than silently following. Attribute lookup is inside this
                // try too: it can throw (entry removed/inaccessible right
                // after enumeration) just like the API calls below, and
                // should be a per-item failure, not a whole-run crash.
                if (subDir.Attributes.HasFlag(FileAttributes.ReparsePoint))
                {
                    stdout.WriteLine($"skip   {subDir.FullName} (symlink)");
                    continue;
                }

                Guid folderId;
                if (existing.TryGetValue(subDir.Name, out var node) && node.IsFolder)
                {
                    folderId = node.Id;
                }
                else
                {
                    folderId = (await api.CreateFolderAsync(remoteParentId, subDir.Name, ct)).Id;
                    stdout.WriteLine($"mkdir  {subDir.FullName}");
                }

                await BackupDirectoryAsync(subDir, folderId, stats, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                stats.Failed++;
                stderr.WriteLine($"ERROR  {subDir.FullName}: {ex.Message}");
            }
        }

        foreach (var file in files)
        {
            ct.ThrowIfCancellationRequested();

            try
            {
                if (file.Attributes.HasFlag(FileAttributes.ReparsePoint))
                {
                    stdout.WriteLine($"skip   {file.FullName} (symlink)");
                    continue;
                }

                await BackupFileAsync(file, remoteParentId, existing.GetValueOrDefault(file.Name), stats, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                stats.Failed++;
                stderr.WriteLine($"ERROR  {file.FullName}: {ex.Message}");
            }
        }
    }

    private async Task BackupFileAsync(FileInfo file, Guid? remoteParentId, FileNode? existing, Stats stats, CancellationToken ct)
    {
        var chunks = await Chunking.ComputeChunksAsync(file.FullName, ct);
        var totalSize = chunks.Sum(c => c.Size);

        Guid fileId;
        if (existing is { IsFolder: false })
        {
            fileId = existing.Id;
            var remote = await api.TryGetManifestAsync(fileId, ct);
            if (remote is not null && Matches(remote.Manifest, chunks, totalSize))
            {
                if (await api.HasVersionAsync(fileId, remote.ManifestHash, ct))
                {
                    stats.Skipped++;
                    stdout.WriteLine($"skip   {file.FullName} (unchanged)");
                    return;
                }

                // Content is already uploaded correctly but a previous run
                // died before recording the FileService version — repair
                // that without re-uploading anything.
                await api.CreateFileVersionAsync(fileId, remote.ManifestHash, remote.Manifest.TotalSize, ct);
                stats.Uploaded++;
                stdout.WriteLine($"repair {file.FullName} (recorded missing version, no re-upload needed)");
                return;
            }
        }
        else
        {
            fileId = (await api.CreateFileNodeAsync(remoteParentId, file.Name, totalSize, ct)).Id;
        }

        var session = await api.InitUploadAsync(fileId, file.Name, chunks.Count, ct);

        // Re-check the length right before re-reading: if the file changed
        // between the hashing pass above and now, uploading the originally
        // planned chunk boundaries against different bytes would silently
        // produce a mismatched snapshot instead of failing loudly.
        if (new FileInfo(file.FullName).Length != totalSize)
            throw new IOException($"'{file.FullName}' changed size while being backed up; skipping this run.");

        await using (var stream = File.OpenRead(file.FullName))
        {
            foreach (var chunk in chunks)
            {
                var buffer = new byte[chunk.Size];
                await ReadExactAsync(stream, buffer, ct);
                await api.UploadChunkAsync(session.SessionId, chunk.Index, buffer, chunk.Hash, ct);
            }
        }

        var complete = await api.CompleteUploadAsync(session.SessionId, ct);
        await api.CreateFileVersionAsync(fileId, complete.ManifestHash, complete.TotalSize, ct);

        stats.Uploaded++;
        stdout.WriteLine($"upload {file.FullName} ({totalSize} bytes)");
    }

    private static bool Matches(RemoteManifest manifest, IReadOnlyList<LocalChunk> chunks, long totalSize)
    {
        if (manifest.TotalSize != totalSize || manifest.Chunks.Count != chunks.Count)
            return false;

        var byIndex = manifest.Chunks.ToDictionary(c => c.Index);
        foreach (var chunk in chunks)
        {
            if (!byIndex.TryGetValue(chunk.Index, out var remote))
                return false;
            if (remote.Size != chunk.Size || !string.Equals(remote.Hash, chunk.Hash, StringComparison.OrdinalIgnoreCase))
                return false;
        }
        return true;
    }

    private static async Task ReadExactAsync(Stream stream, byte[] buffer, CancellationToken ct)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(total, buffer.Length - total), ct);
            if (read == 0)
                throw new IOException("File changed size while it was being read for upload.");
            total += read;
        }
    }

    private sealed class Stats
    {
        public int Uploaded;
        public int Skipped;
        public int Failed;
    }
}
