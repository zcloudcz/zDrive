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
    /// checked when MinRetentionDays is zero or negative. Composes onto the
    /// caller's query so the database returns only the prunable rows — with a
    /// minimum age set, the versions it keeps are not bounded in number.
    /// </summary>
    public static IQueryable<FileVersion> SelectPrunable(
        IQueryable<FileVersion> existing, VersioningOptions options, DateTime utcNow)
    {
        if (options.MaxVersionsPerFile <= 0)
            return existing.Where(_ => false);

        var beyondLimit = existing
            .OrderByDescending(v => v.VersionNumber)
            .Skip(options.MaxVersionsPerFile - 1);

        if (options.MinRetentionDays > 0)
        {
            // A minimum age reaching back before DateTime.MinValue (e.g. a
            // huge value meant as "keep forever") would make AddDays throw;
            // nothing can be that old, so nothing is prunable.
            if (options.MinRetentionDays >= (utcNow - DateTime.MinValue).TotalDays)
                return existing.Where(_ => false);

            var cutoff = utcNow.AddDays(-options.MinRetentionDays);
            beyondLimit = beyondLimit.Where(v => v.CreatedAt < cutoff);
        }

        return beyondLimit;
    }
}
