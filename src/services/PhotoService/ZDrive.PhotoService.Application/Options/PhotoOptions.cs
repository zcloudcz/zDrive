namespace ZDrive.PhotoService.Application.Options;

/// <summary>Bound from <c>Photos:Ingest</c>.</summary>
public sealed class PhotoIngestOptions
{
    public const string SectionName = "Photos:Ingest";

    /// <summary>Tests switch the background loop off and drive the pump directly.</summary>
    public bool Enabled { get; set; } = true;
    public int PollIntervalSeconds { get; set; } = 5;
    public int BatchSize { get; set; } = 500;
    public int MaxConcurrentProcessing { get; set; } = 2;
    public long MaxSourceBytes { get; set; } = 100 * 1024 * 1024;
    public int LeaseMinutes { get; set; } = 10;
    public int MaxAttempts { get; set; } = 3;
}

/// <summary>Bound from <c>Photos:Thumbnails</c>.</summary>
public sealed class PhotoThumbnailOptions
{
    public const string SectionName = "Photos:Thumbnails";

    public int CacheMaxAgeSeconds { get; set; } = 3600;
}
