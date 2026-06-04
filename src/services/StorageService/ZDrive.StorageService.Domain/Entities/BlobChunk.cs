namespace ZDrive.StorageService.Domain.Entities;

public sealed class BlobChunk
{
    public Guid Id { get; set; }
    public Guid FileId { get; set; }
    public string ChunkHash { get; set; } = string.Empty;
    public int ChunkIndex { get; set; }
    public long SizeBytes { get; set; }
    public string BlobPath { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
