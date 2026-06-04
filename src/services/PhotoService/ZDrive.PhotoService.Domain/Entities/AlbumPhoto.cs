namespace ZDrive.PhotoService.Domain.Entities;

public sealed class AlbumPhoto
{
    public Guid AlbumId { get; set; }
    public Guid PhotoId { get; set; }
    public int SortOrder { get; set; }
    public DateTime AddedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public Album? Album { get; set; }
    public Photo? Photo { get; set; }
}
