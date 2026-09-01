using System.Security.Cryptography;
using ZDrive.BackupCli.Api;

namespace ZDrive.BackupCli.Tests.Unit;

/// <summary>
/// In-memory stand-in for the real API, just enough to exercise BackupRunner's
/// mirroring/idempotence decisions without any network or Testcontainers.
/// </summary>
public sealed class FakeZdriveApiClient : IZdriveApiClient
{
    private readonly List<FileNode> _nodes = [];
    private readonly Dictionary<Guid, RemoteManifestResult> _manifests = [];
    private readonly Dictionary<Guid, HashSet<string>> _versionsByFile = [];
    private readonly Dictionary<Guid, byte[]> _content = [];
    private readonly Dictionary<Guid, byte[]?[]> _sessionChunks = [];
    private readonly Dictionary<Guid, Guid> _sessionFileId = [];

    public int CreateFileNodeCalls { get; private set; }
    public int InitUploadCalls { get; private set; }
    public int CreateFileVersionCalls { get; private set; }

    /// <summary>Fault injection for partial-failure tests: throws instead of creating a folder with this name.</summary>
    public string? FailFolderName { get; set; }

    /// <summary>Fault injection for partial-failure tests: throws instead of creating a file node with this name.</summary>
    public string? FailFileName { get; set; }

    /// <summary>Fault injection for partial-failure tests: throws instead of listing the children of the folder with this name.</summary>
    public string? FailListChildrenForFolderName { get; set; }

    public byte[] GetUploadedContent(Guid fileId) => _content[fileId];

    public Task<IReadOnlyDictionary<string, FileNode>> ListChildrenAsync(Guid? parentId, CancellationToken ct)
    {
        if (parentId is { } id && _nodes.FirstOrDefault(n => n.Id == id) is { Name: var name } && name == FailListChildrenForFolderName)
            throw new IOException($"Simulated listing failure for '{name}'.");

        IReadOnlyDictionary<string, FileNode> result =
            _nodes.Where(n => n.ParentId == parentId).ToDictionary(n => n.Name);
        return Task.FromResult(result);
    }

    public Task<FileNode> CreateFolderAsync(Guid? parentId, string name, CancellationToken ct)
    {
        if (name == FailFolderName)
            throw new IOException($"Simulated folder creation failure for '{name}'.");

        var node = new FileNode(Guid.NewGuid(), name, true, null, null, parentId, DateTime.UtcNow, DateTime.UtcNow, false);
        _nodes.Add(node);
        return Task.FromResult(node);
    }

    public Task<FileNode> CreateFileNodeAsync(Guid? parentId, string name, long sizeBytes, CancellationToken ct)
    {
        if (name == FailFileName)
            throw new IOException($"Simulated file upload failure for '{name}'.");

        CreateFileNodeCalls++;
        var node = new FileNode(Guid.NewGuid(), name, false, sizeBytes, null, parentId, DateTime.UtcNow, DateTime.UtcNow, false);
        _nodes.Add(node);
        return Task.FromResult(node);
    }

    public Task CreateFileVersionAsync(Guid fileId, string manifestHash, long sizeBytes, CancellationToken ct)
    {
        CreateFileVersionCalls++;
        if (!_versionsByFile.TryGetValue(fileId, out var hashes))
            _versionsByFile[fileId] = hashes = [];
        hashes.Add(manifestHash);
        return Task.CompletedTask;
    }

    public Task<UploadSession> InitUploadAsync(Guid fileId, string fileName, int totalChunks, CancellationToken ct)
    {
        InitUploadCalls++;
        var sessionId = Guid.NewGuid();
        _sessionChunks[sessionId] = new byte[totalChunks][];
        _sessionFileId[sessionId] = fileId;
        return Task.FromResult(new UploadSession(sessionId, "fake://upload"));
    }

    public Task UploadChunkAsync(Guid sessionId, int index, byte[] data, string chunkHash, CancellationToken ct)
    {
        _sessionChunks[sessionId][index] = data;
        return Task.CompletedTask;
    }

    public Task<UploadComplete> CompleteUploadAsync(Guid sessionId, CancellationToken ct)
    {
        var chunks = _sessionChunks[sessionId];
        var fileId = _sessionFileId[sessionId];

        using var full = new MemoryStream();
        var chunkInfos = new List<RemoteChunk>();
        for (var i = 0; i < chunks.Length; i++)
        {
            var bytes = chunks[i] ?? throw new InvalidOperationException($"Chunk {i} was never uploaded.");
            var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            chunkInfos.Add(new RemoteChunk(hash, i, bytes.Length));
            full.Write(bytes);
        }

        _content[fileId] = full.ToArray();
        var manifestHash = Guid.NewGuid().ToString("N");
        _manifests[fileId] = new RemoteManifestResult(new RemoteManifest(fileId, full.Length, chunkInfos), manifestHash);
        return Task.FromResult(new UploadComplete($"blob/{fileId}", manifestHash, full.Length));
    }

    public Task<RemoteManifestResult?> TryGetManifestAsync(Guid fileId, CancellationToken ct) =>
        Task.FromResult(_manifests.GetValueOrDefault(fileId));

    public Task<bool> HasVersionAsync(Guid fileId, string manifestHash, CancellationToken ct) =>
        Task.FromResult(_versionsByFile.TryGetValue(fileId, out var hashes) && hashes.Contains(manifestHash));
}
