using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Application.Options;

/// <summary>
/// Single definition of which existing versions a write may prune, shared by
/// CreateFileVersion and RestoreFileVersion.
/// </summary>
public static class VersionRetention
{
    /// <summary>
    /// Versions beyond the newest MaxVersionsPerFile that are also older than
    /// MinRetentionDays. The version being written reserves one slot, so the
    /// newest MaxVersionsPerFile - 1 existing rows are always kept (the
    /// current version is among them unless the limit is 1, in which case the
    /// new version replaces it and only its age protects it). Age is not
    /// checked when MinRetentionDays is zero or negative.
    /// </summary>
    public static List<FileVersion> SelectPrunable(
        IEnumerable<FileVersion> existing, VersioningOptions options, DateTime utcNow)
    {
        if (options.MaxVersionsPerFile <= 0)
            return [];

        var beyondLimit = existing
            .OrderByDescending(v => v.VersionNumber)
            .Skip(options.MaxVersionsPerFile - 1);

        if (options.MinRetentionDays > 0)
        {
            var cutoff = utcNow.AddDays(-options.MinRetentionDays);
            beyondLimit = beyondLimit.Where(v => v.CreatedAt < cutoff);
        }

        return beyondLimit.ToList();
    }
}
