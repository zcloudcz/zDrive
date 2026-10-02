using System.Globalization;
using System.Runtime.InteropServices;
using MetadataExtractor;
using MetadataExtractor.Formats.Exif;
using MetadataExtractor.Util;
using SkiaSharp;
using ZDrive.PhotoService.Application.Common;
using ZDrive.PhotoService.Application.Interfaces.Ingest;

namespace ZDrive.PhotoService.Infrastructure.Ingest;

/// <summary>
/// MetadataExtractor (Apache-2.0) for EXIF, SkiaSharp (MIT) for decoding,
/// orientation and WebP thumbnails.
/// </summary>
public sealed class SkiaPhotoImageProcessor : IPhotoImageProcessor
{
    private const int WebpQuality = 80;
    private static readonly float[] DownscaleSteps = [0.125f, 0.25f, 0.5f];

    private readonly long _maxDecodedPixels;

    public SkiaPhotoImageProcessor(long maxDecodedPixels = 40_000_000) => _maxDecodedPixels = maxDecodedPixels;

    public PhotoProcessingResult Process(byte[] source)
    {
        var exif = ReadMetadata(source, out var recognisedButUndecodable);

        // Skia reads straight from the caller's buffer (pinned for the duration
        // of this call) instead of copying the whole original again.
        var handle = GCHandle.Alloc(source, GCHandleType.Pinned);
        try
        {
            using var data = SKData.Create(handle.AddrOfPinnedObject(), source.Length, null!);
            using var codec = SKCodec.Create(data);
            if (codec is null)
            {
                // HEIC/HEIF/AVIF: Skia has no decoder on Linux. Keep the EXIF
                // (date, GPS, camera), skip thumbnails.
                if (recognisedButUndecodable)
                    return exif with { Thumbnails = new Dictionary<int, byte[]>() };
                throw new PermanentPhotoException("Unsupported or corrupt image.");
            }

            var origin = codec.EncodedOrigin;
            var swap = origin >= SKEncodedOrigin.LeftTop;
            var fullWidth = swap ? codec.Info.Height : codec.Info.Width;
            var fullHeight = swap ? codec.Info.Width : codec.Info.Height;

            using var decoded = Decode(codec, _maxDecodedPixels)
                ?? throw new PermanentPhotoException("Image could not be decoded.");
            var oriented = ApplyOrigin(decoded, origin);
            try
            {
                var thumbnails = new Dictionary<int, byte[]>();
                foreach (var size in ThumbnailSizes.All)
                    thumbnails[size] = RenderWebp(oriented, size);

                return exif with
                {
                    Width = fullWidth,
                    Height = fullHeight,
                    Orientation = (int)origin,
                    Thumbnails = thumbnails,
                };
            }
            finally
            {
                if (!ReferenceEquals(oriented, decoded))
                    oriented.Dispose();
            }
        }
        finally
        {
            handle.Free();
        }
    }

    private static PhotoProcessingResult ReadMetadata(byte[] source, out bool recognisedButUndecodable)
    {
        recognisedButUndecodable = false;
        IReadOnlyList<MetadataExtractor.Directory> dirs;
        try
        {
            using var ms = new MemoryStream(source, writable: false);
            var fileType = FileTypeDetector.DetectFileType(ms);
            recognisedButUndecodable = fileType is FileType.Heif or FileType.Avif;
            ms.Position = 0;
            dirs = ImageMetadataReader.ReadMetadata(ms);
        }
        catch (Exception)
        {
            // Metadata is best effort (parsers throw many exception types on
            // malformed input); decoding decides whether the image is usable.
            return Empty();
        }

        var ifd0 = dirs.OfType<ExifIfd0Directory>().FirstOrDefault();
        var sub = dirs.OfType<ExifSubIfdDirectory>().FirstOrDefault();

        DateTime? takenAt = null;
        double? lat = null, lng = null;
        try
        {
            if (sub is not null && sub.TryGetDateTime(ExifDirectoryBase.TagDateTimeOriginal, out var local))
                takenAt = ToUtc(local, sub.GetString(ExifDirectoryBase.TagTimeZoneOriginal));

            var geo = dirs.OfType<GpsDirectory>().FirstOrDefault()?.GetGeoLocation();
            (lat, lng) = (geo?.Latitude, geo?.Longitude);
        }
        catch (Exception)
        {
            // A bad timestamp or coordinate must never fail the photo: keep what parsed.
        }

        return Empty() with
        {
            TakenAtUtc = takenAt,
            Lat = lat,
            Lng = lng,
            CameraMake = Truncate(ifd0?.GetString(ExifDirectoryBase.TagMake)),
            CameraModel = Truncate(ifd0?.GetString(ExifDirectoryBase.TagModel)),
        };
    }

    private static PhotoProcessingResult Empty() =>
        new(null, null, null, null, null, null, null, null, new Dictionary<int, byte[]>());

    private static string? Truncate(string? value)
    {
        value = value?.Trim();
        if (string.IsNullOrEmpty(value)) return null;
        return value.Length <= 256 ? value : value[..256];
    }

    /// <summary>
    /// EXIF DateTimeOriginal has no zone. Use OffsetTimeOriginal ("+02:00")
    /// when the camera wrote a valid one, otherwise treat the wall clock as
    /// UTC. Never throws: an out-of-range offset (DateTimeOffset allows only
    /// +-14:00) or a date whose UTC equivalent leaves the DateTime range falls
    /// back to the wall-clock reading.
    /// </summary>
    public static DateTime ToUtc(DateTime local, string? offsetTag)
    {
        var wallClock = DateTime.SpecifyKind(local, DateTimeKind.Utc);
        if (!TryParseOffset(offsetTag, out var offset))
            return wallClock;

        try
        {
            return new DateTimeOffset(DateTime.SpecifyKind(local, DateTimeKind.Unspecified), offset).UtcDateTime;
        }
        catch (ArgumentException)
        {
            return wallClock;
        }
    }

    private static bool TryParseOffset(string? tag, out TimeSpan offset)
    {
        offset = default;
        var text = tag?.Trim();
        if (string.IsNullOrEmpty(text) || text[0] is not ('+' or '-'))
            return false;
        if (!TimeSpan.TryParseExact(text[1..], @"hh\:mm", CultureInfo.InvariantCulture, out var magnitude))
            return false;
        offset = text[0] == '-' ? -magnitude : magnitude;
        return true;
    }

    /// <summary>
    /// Decodes at the smallest codec-supported scale (JPEG DCT scaling, WebP)
    /// that still has at least the largest thumbnail's worth of pixels: much
    /// less memory and CPU for multi-megapixel originals. Formats that cannot
    /// scale (PNG) report their own size and decode in full — bounded by the
    /// pixel cap.
    /// </summary>
    private static SKBitmap? Decode(SKCodec codec, long maxDecodedPixels)
    {
        var info = codec.Info;
        var target = ThumbnailSizes.All.Max();
        foreach (var scale in DownscaleSteps)
        {
            var dims = codec.GetScaledDimensions(scale);
            if (dims.Width > 0 && dims.Height > 0 && Math.Max(dims.Width, dims.Height) >= target)
            {
                info = info.WithSize(dims.Width, dims.Height);
                break;
            }
        }

        // Decompression-bomb guard on the size actually decoded, checked BEFORE
        // the pixel buffer is allocated. Capping the declared size instead
        // would reject a 50 MP camera JPEG that decodes at 1/4 scale for a few
        // MB, while the real memory risk is formats that cannot scale (PNG).
        var pixels = (long)info.Width * info.Height;
        if (pixels > maxDecodedPixels)
            throw new PermanentPhotoException(
                $"TooManyPixels: image decodes at {info.Width}x{info.Height} ({pixels} pixels), limit is {maxDecodedPixels}.");

        var bitmap = new SKBitmap(info);
        var result = codec.GetPixels(info, bitmap.GetPixels());
        if (result is SKCodecResult.Success or SKCodecResult.IncompleteInput)
            return bitmap;

        bitmap.Dispose();
        return null;
    }

    /// <summary>
    /// Rotates/flips the decoded pixels so they are displayed upright (EXIF
    /// orientations 1-8). Returns <paramref name="src"/> itself when nothing
    /// has to change; the caller disposes the result only if it is a different instance.
    /// </summary>
    public static SKBitmap ApplyOrigin(SKBitmap src, SKEncodedOrigin origin)
    {
        if (origin == SKEncodedOrigin.TopLeft)
            return src;

        float w = src.Width, h = src.Height;
        var swap = origin >= SKEncodedOrigin.LeftTop;
        var dst = new SKBitmap(swap ? src.Height : src.Width, swap ? src.Width : src.Height, src.ColorType, src.AlphaType);

        // x' = ScaleX*x + SkewX*y + TransX ; y' = SkewY*x + ScaleY*y + TransY
        var m = origin switch
        {
            SKEncodedOrigin.TopRight => new SKMatrix { ScaleX = -1, TransX = w, ScaleY = 1, Persp2 = 1 },
            SKEncodedOrigin.BottomRight => new SKMatrix { ScaleX = -1, TransX = w, ScaleY = -1, TransY = h, Persp2 = 1 },
            SKEncodedOrigin.BottomLeft => new SKMatrix { ScaleX = 1, ScaleY = -1, TransY = h, Persp2 = 1 },
            SKEncodedOrigin.LeftTop => new SKMatrix { SkewX = 1, SkewY = 1, Persp2 = 1 },
            SKEncodedOrigin.RightTop => new SKMatrix { SkewX = -1, TransX = h, SkewY = 1, Persp2 = 1 },
            SKEncodedOrigin.RightBottom => new SKMatrix { SkewX = -1, TransX = h, SkewY = -1, TransY = w, Persp2 = 1 },
            SKEncodedOrigin.LeftBottom => new SKMatrix { SkewX = 1, SkewY = -1, TransY = w, Persp2 = 1 },
            _ => SKMatrix.Identity,
        };

        using var canvas = new SKCanvas(dst);
        canvas.SetMatrix(m);
        using var image = SKImage.FromBitmap(src);
        canvas.DrawImage(image, 0, 0, new SKSamplingOptions(SKFilterMode.Nearest));
        return dst;
    }

    private static byte[] RenderWebp(SKBitmap oriented, int size)
    {
        var longest = Math.Max(oriented.Width, oriented.Height);
        // Never upscale: a small original keeps its own size (and is encoded as is).
        var scale = Math.Min(1f, (float)size / longest);
        if (scale >= 1f)
            return EncodeWebp(oriented);

        var width = Math.Max(1, (int)Math.Round(oriented.Width * scale));
        var height = Math.Max(1, (int)Math.Round(oriented.Height * scale));
        using var resized = oriented.Resize(oriented.Info.WithSize(width, height), new SKSamplingOptions(SKCubicResampler.Mitchell))
            ?? throw new PermanentPhotoException("Image could not be resized.");
        return EncodeWebp(resized);
    }

    private static byte[] EncodeWebp(SKBitmap bitmap)
    {
        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Webp, WebpQuality)
            ?? throw new PermanentPhotoException("Thumbnail could not be encoded.");
        return data.ToArray();
    }
}
