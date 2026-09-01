using System.Security.Cryptography;

namespace ZDrive.BackupCli.Backup;

public sealed record LocalChunk(int Index, long Size, string Hash);

/// <summary>
/// Splits a file into ~4 MB chunks and SHA-256-hashes each one, matching the
/// chunk size the Flutter client's upload flow and StorageService assume
/// (see CLAUDE.md "Blob versioning" / docs/release-test-deploy.md).
/// </summary>
public static class Chunking
{
    public const int ChunkSize = 4 * 1024 * 1024;

    /// <summary>
    /// Streams the file in ChunkSize windows, hashing each without holding
    /// more than one chunk in memory at a time. Empty files still produce
    /// exactly one (zero-byte) chunk — StorageService requires totalChunks > 0.
    /// </summary>
    public static async Task<IReadOnlyList<LocalChunk>> ComputeChunksAsync(string path, CancellationToken ct)
    {
        var chunks = new List<LocalChunk>();
        await using var stream = File.OpenRead(path);
        var buffer = new byte[ChunkSize];
        var index = 0;

        int read;
        while ((read = await ReadFullyAsync(stream, buffer, ct)) > 0)
        {
            var hash = Convert.ToHexString(SHA256.HashData(buffer.AsSpan(0, read))).ToLowerInvariant();
            chunks.Add(new LocalChunk(index, read, hash));
            index++;
        }

        if (chunks.Count == 0)
            chunks.Add(new LocalChunk(0, 0, Convert.ToHexString(SHA256.HashData([])).ToLowerInvariant()));

        return chunks;
    }

    private static async Task<int> ReadFullyAsync(Stream stream, byte[] buffer, CancellationToken ct)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(total, buffer.Length - total), ct);
            if (read == 0)
                break;
            total += read;
        }
        return total;
    }
}
