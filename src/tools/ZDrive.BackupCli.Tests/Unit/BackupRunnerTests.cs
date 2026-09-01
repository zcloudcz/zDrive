using System.Text;
using FluentAssertions;
using ZDrive.BackupCli.Backup;

namespace ZDrive.BackupCli.Tests.Unit;

public sealed class BackupRunnerTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("zdrive-backup-tests-").FullName;
    private readonly FakeZdriveApiClient _api = new();
    private readonly StringWriter _stdout = new();
    private readonly StringWriter _stderr = new();

    private BackupRunner Runner => new(_api, _stdout, _stderr);

    public void Dispose() => Directory.Delete(_root, recursive: true);

    [Fact]
    public async Task RunAsync_NestedDirectories_MirrorsStructureAndUploadsContent()
    {
        Directory.CreateDirectory(Path.Combine(_root, "sub"));
        await File.WriteAllTextAsync(Path.Combine(_root, "top.txt"), "top level");
        await File.WriteAllTextAsync(Path.Combine(_root, "sub", "nested.txt"), "nested content");

        var exitCode = await Runner.RunAsync(_root, destPath: null, CancellationToken.None);

        exitCode.Should().Be(0);
        var rootChildren = await _api.ListChildrenAsync(null, CancellationToken.None);
        rootChildren.Should().ContainKey("top.txt");
        rootChildren.Should().ContainKey("sub");
        rootChildren["sub"].IsFolder.Should().BeTrue();

        var subChildren = await _api.ListChildrenAsync(rootChildren["sub"].Id, CancellationToken.None);
        subChildren.Should().ContainKey("nested.txt");

        Encoding.UTF8.GetString(_api.GetUploadedContent(rootChildren["top.txt"].Id)).Should().Be("top level");
        Encoding.UTF8.GetString(_api.GetUploadedContent(subChildren["nested.txt"].Id)).Should().Be("nested content");
    }

    [Fact]
    public async Task RunAsync_CalledTwice_SecondRunSkipsUnchangedFiles()
    {
        await File.WriteAllTextAsync(Path.Combine(_root, "file.txt"), "same content every time");

        (await Runner.RunAsync(_root, null, CancellationToken.None)).Should().Be(0);
        _api.InitUploadCalls.Should().Be(1);
        _api.CreateFileNodeCalls.Should().Be(1);

        (await Runner.RunAsync(_root, null, CancellationToken.None)).Should().Be(0);

        // No new upload session and no duplicate node for the unchanged file.
        _api.InitUploadCalls.Should().Be(1);
        _api.CreateFileNodeCalls.Should().Be(1);
        _stdout.ToString().Should().Contain("skip");
    }

    [Fact]
    public async Task RunAsync_FileContentChanged_ReUploadsAsNewVersionOnSameNode()
    {
        var path = Path.Combine(_root, "file.txt");
        await File.WriteAllTextAsync(path, "version one");
        await Runner.RunAsync(_root, null, CancellationToken.None);

        var nodeIdBefore = (await _api.ListChildrenAsync(null, CancellationToken.None))["file.txt"].Id;

        await File.WriteAllTextAsync(path, "version two — different length and content");
        await Runner.RunAsync(_root, null, CancellationToken.None);

        var nodeIdAfter = (await _api.ListChildrenAsync(null, CancellationToken.None))["file.txt"].Id;
        nodeIdAfter.Should().Be(nodeIdBefore, "changed content should create a new version, not a duplicate file node");
        _api.CreateFileNodeCalls.Should().Be(1);
        _api.InitUploadCalls.Should().Be(2);
        _api.CreateFileVersionCalls.Should().Be(2);
        Encoding.UTF8.GetString(_api.GetUploadedContent(nodeIdAfter)).Should().Be("version two — different length and content");
    }

    [Fact]
    public async Task RunAsync_NodeExistsWithoutManifest_ResumesInterruptedUploadOnSameNode()
    {
        // Simulates a previous run that was killed after creating the file
        // node but before the upload ever completed (no manifest recorded).
        var path = Path.Combine(_root, "partial.txt");
        var contentBytes = Encoding.UTF8.GetBytes("content that never finished uploading");
        await File.WriteAllBytesAsync(path, contentBytes);
        var preExistingNode = await _api.CreateFileNodeAsync(null, "partial.txt", contentBytes.Length, CancellationToken.None);

        var exitCode = await Runner.RunAsync(_root, null, CancellationToken.None);

        exitCode.Should().Be(0);
        _api.CreateFileNodeCalls.Should().Be(1, "the pre-existing node must be reused, not duplicated");
        var children = await _api.ListChildrenAsync(null, CancellationToken.None);
        children.Should().HaveCount(1);
        children["partial.txt"].Id.Should().Be(preExistingNode.Id);
        _api.GetUploadedContent(preExistingNode.Id).Should().BeEquivalentTo(contentBytes);
    }

    [Fact]
    public async Task RunAsync_ManifestCompleteButVersionMissing_RecordsVersionWithoutReupload()
    {
        // Simulates a run that finished the StorageService upload (manifest
        // written) but died before the separate FileService
        // CreateFileVersion call — the two are not atomic.
        var path = Path.Combine(_root, "file.txt");
        var contentBytes = Encoding.UTF8.GetBytes("uploaded but never versioned");
        await File.WriteAllBytesAsync(path, contentBytes);

        var node = await _api.CreateFileNodeAsync(null, "file.txt", contentBytes.Length, CancellationToken.None);
        var session = await _api.InitUploadAsync(node.Id, "file.txt", 1, CancellationToken.None);
        await _api.UploadChunkAsync(session.SessionId, 0, contentBytes, "unused", CancellationToken.None);
        await _api.CompleteUploadAsync(session.SessionId, CancellationToken.None);
        // Deliberately no CreateFileVersionAsync call here.

        var exitCode = await Runner.RunAsync(_root, null, CancellationToken.None);

        exitCode.Should().Be(0);
        _api.CreateFileNodeCalls.Should().Be(1, "the existing node must be reused");
        _api.InitUploadCalls.Should().Be(1, "content already matches — no re-upload needed, only the missing version");
        _api.CreateFileVersionCalls.Should().Be(1);
        _stdout.ToString().Should().Contain("repair");
    }

    [Fact]
    public async Task RunAsync_DestPath_CreatesNestedRemoteFolders()
    {
        await File.WriteAllTextAsync(Path.Combine(_root, "photo.jpg"), "binary-ish content");

        await Runner.RunAsync(_root, "backup/photos", CancellationToken.None);

        var rootChildren = await _api.ListChildrenAsync(null, CancellationToken.None);
        rootChildren.Should().ContainKey("backup");
        var backupChildren = await _api.ListChildrenAsync(rootChildren["backup"].Id, CancellationToken.None);
        backupChildren.Should().ContainKey("photos");
        var photosChildren = await _api.ListChildrenAsync(backupChildren["photos"].Id, CancellationToken.None);
        photosChildren.Should().ContainKey("photo.jpg");
    }
}
