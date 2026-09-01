namespace ZDrive.BackupCli.Api;

/// <summary>Extracted purely so BackupRunner's decision logic is unit-testable without real HTTP.</summary>
public interface IZdriveApiClient
{
    Task<IReadOnlyDictionary<string, FileNode>> ListChildrenAsync(Guid? parentId, CancellationToken ct);
    Task<FileNode> CreateFolderAsync(Guid? parentId, string name, CancellationToken ct);
    Task<FileNode> CreateFileNodeAsync(Guid? parentId, string name, long sizeBytes, CancellationToken ct);
    Task CreateFileVersionAsync(Guid fileId, string manifestHash, long sizeBytes, CancellationToken ct);
    Task<UploadSession> InitUploadAsync(Guid fileId, string fileName, int totalChunks, CancellationToken ct);
    Task UploadChunkAsync(Guid sessionId, int index, byte[] data, string chunkHash, CancellationToken ct);
    Task<UploadComplete> CompleteUploadAsync(Guid sessionId, CancellationToken ct);
    Task<RemoteManifestResult?> TryGetManifestAsync(Guid fileId, CancellationToken ct);
    Task<bool> HasVersionAsync(Guid fileId, string manifestHash, CancellationToken ct);
}
