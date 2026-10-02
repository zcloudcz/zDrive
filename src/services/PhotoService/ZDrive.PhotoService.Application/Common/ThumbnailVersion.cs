namespace ZDrive.PhotoService.Application.Common;

public static class ThumbnailVersion
{
    /// <summary>Blob path segment for thumbnails generated from this manifest hash.</summary>
    public static string Of(string manifestHash) => manifestHash[..Math.Min(16, manifestHash.Length)];
}
