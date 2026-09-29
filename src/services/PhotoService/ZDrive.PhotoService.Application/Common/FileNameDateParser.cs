using System.Globalization;
using System.Text.RegularExpressions;

namespace ZDrive.PhotoService.Application.Common;

/// <summary>Last-resort capture date for images without EXIF.</summary>
public static partial class FileNameDateParser
{
    /// <summary>
    /// Attempts to extract a date/time from the file name when no EXIF data is available.
    /// Supports patterns like: IMG_20231225_143022, 2023-12-25_14-30-22, 20231225_143022.
    /// </summary>
    public static DateTime? TryParse(string fileName)
    {
        var name = Path.GetFileNameWithoutExtension(fileName);

        // Pattern: 20231225_143022 or IMG_20231225_143022
        var match = DateTimePattern().Match(name);
        if (match.Success)
        {
            var dateStr = $"{match.Groups[1].Value}-{match.Groups[2].Value}-{match.Groups[3].Value} " +
                          $"{match.Groups[4].Value}:{match.Groups[5].Value}:{match.Groups[6].Value}";

            if (DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dt))
                return DateTime.SpecifyKind(dt, DateTimeKind.Utc);
        }

        // Pattern: 2023-12-25_14-30-22 or 2023-12-25 14-30-22
        var dashMatch = DashDateTimePattern().Match(name);
        if (dashMatch.Success)
        {
            var dateStr = $"{dashMatch.Groups[1].Value}-{dashMatch.Groups[2].Value}-{dashMatch.Groups[3].Value} " +
                          $"{dashMatch.Groups[4].Value}:{dashMatch.Groups[5].Value}:{dashMatch.Groups[6].Value}";

            if (DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dt))
                return DateTime.SpecifyKind(dt, DateTimeKind.Utc);
        }

        return null;
    }

    // 20231225_143022 — optionally preceded by prefix like IMG_
    [GeneratedRegex(@"(\d{4})(\d{2})(\d{2})[_\-](\d{2})(\d{2})(\d{2})")]
    private static partial Regex DateTimePattern();

    // 2023-12-25_14-30-22
    [GeneratedRegex(@"(\d{4})-(\d{2})-(\d{2})[_ ](\d{2})-(\d{2})-(\d{2})")]
    private static partial Regex DashDateTimePattern();
}
