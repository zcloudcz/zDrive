namespace ZDrive.StorageService.Domain.ValueObjects;

public sealed class ChunkManifest
{
    public Guid FileId { get; init; }
    public long TotalSize { get; init; }
    public List<ChunkInfo> Chunks { get; init; } = [];
}

public sealed class ChunkInfo
{
    public string Hash { get; init; } = string.Empty;
    public int Index { get; init; }
    public long Size { get; init; }
}
