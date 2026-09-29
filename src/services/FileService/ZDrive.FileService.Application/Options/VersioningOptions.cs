namespace ZDrive.FileService.Application.Options;

/// <summary>
/// Retention policy for file versions. Bound from the "Versioning"
/// configuration section (per-deployment; per-tenant overrides are a later
/// phase-7 concern).
/// </summary>
public sealed class VersioningOptions
{
    public const string SectionName = "Versioning";

    /// <summary>
    /// Maximum number of versions kept per file. When a new version is
    /// recorded the oldest rows beyond this limit are pruned.
    /// Zero or negative disables pruning.
    /// </summary>
    public int MaxVersionsPerFile { get; set; } = 10;

    /// <summary>
    /// Minimum age in days before a version may be pruned. A version is only
    /// pruned when it is beyond the newest MaxVersionsPerFile AND older than
    /// this many days, so MaxVersionsPerFile is NOT a hard cap when young
    /// versions exceed it. Zero or negative (default) means age is ignored.
    /// </summary>
    public int MinRetentionDays { get; set; } = 0;
}
