namespace ZDrive.FileService.Application.Options;

/// <summary>
/// Per-user storage quota fallback. Bound from the "Storage" configuration
/// section, used only when the caller's JWT carries no quota_bytes claim
/// (subscription plans will start setting that claim later).
/// </summary>
public sealed class StorageOptions
{
    public const string SectionName = "Storage";

    /// <summary>Default quota per user, in bytes. 50 GiB.</summary>
    public long DefaultUserQuotaBytes { get; set; } = 53687091200;
}
