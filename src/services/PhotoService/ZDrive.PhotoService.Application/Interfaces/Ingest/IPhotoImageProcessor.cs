namespace ZDrive.PhotoService.Application.Interfaces.Ingest;

public interface IPhotoImageProcessor
{
    /// <summary>
    /// Extracts metadata and renders thumbnails. Throws
    /// <see cref="PermanentPhotoException"/> for undecodable input.
    /// Formats that are recognised but cannot be decoded on this platform
    /// (HEIC/AVIF on Linux) return metadata with an empty
    /// <see cref="PhotoProcessingResult.Thumbnails"/>.
    /// </summary>
    PhotoProcessingResult Process(byte[] source);
}

public sealed record PhotoProcessingResult(
    DateTime? TakenAtUtc,
    double? Lat,
    double? Lng,
    string? CameraMake,
    string? CameraModel,
    int? Width,
    int? Height,
    int? Orientation,
    IReadOnlyDictionary<int, byte[]> Thumbnails);

/// <summary>Retrying cannot succeed (corrupt data, hash mismatch, too large); the photo goes straight to Failed.</summary>
public sealed class PermanentPhotoException(string message, Exception? inner = null) : Exception(message, inner);
