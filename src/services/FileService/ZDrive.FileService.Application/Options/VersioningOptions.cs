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
}
