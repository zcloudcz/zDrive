namespace ZDrive.PhotoService.Application.Common;

public static class ImageFileTypes
{
    private static readonly HashSet<string> Extensions =
        new(StringComparer.OrdinalIgnoreCase) { ".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp" };

    /// <summary>An image by MIME type, otherwise by file extension.</summary>
    public static bool IsImage(string fileName, string? mimeType) =>
        mimeType?.StartsWith("image/", StringComparison.OrdinalIgnoreCase) == true
        || Extensions.Contains(Path.GetExtension(fileName));
}
