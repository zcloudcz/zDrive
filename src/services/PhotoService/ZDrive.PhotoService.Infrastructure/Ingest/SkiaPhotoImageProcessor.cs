using System.Globalization;
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

    public PhotoProcessingResult Process(byte[] source)
    {
        var exif = ReadMetadata(source, out var recognisedButUndecodable);

        using var codec = SKCodec.Create(new SKMemoryStream(source));
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

        using var decoded = Decode(codec)
            ?? throw new PermanentPhotoException("Image could not be decoded.");
        using var oriented = ApplyOrigin(decoded, origin);

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
        var geo = dirs.OfType<GpsDirectory>().FirstOrDefault()?.GetGeoLocation();

        DateTime? takenAt = null;
        if (sub is not null && sub.TryGetDateTime(ExifDirectoryBase.TagDateTimeOriginal, out var local))
            takenAt = ToUtc(local, sub.GetString(ExifDirectoryBase.TagTimeZoneOriginal));

        return Empty() with
        {
            TakenAtUtc = takenAt,
            Lat = geo?.Latitude,
            Lng = geo?.Longitude,
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
    /// when the camera wrote it, otherwise treat the wall clock as UTC.
    /// </summary>
    public static DateTime ToUtc(DateTime local, string? offsetTag)
    {
        var unspecified = DateTime.SpecifyKind(local, DateTimeKind.Unspecified);
        if (offsetTag is not null
            && TimeSpan.TryParseExact(offsetTag.Trim().TrimStart('+'), @"hh\:mm", CultureInfo.InvariantCulture, out var positive)
            && !offsetTag.Trim().StartsWith('-'))
            return new DateTimeOffset(unspecified, positive).UtcDateTime;
        if (offsetTag is not null && offsetTag.Trim().StartsWith('-')
            && TimeSpan.TryParseExact(offsetTag.Trim().TrimStart('-'), @"hh\:mm", CultureInfo.InvariantCulture, out var negative))
            return new DateTimeOffset(unspecified, -negative).UtcDateTime;
        return DateTime.SpecifyKind(local, DateTimeKind.Utc);
    }

    /// <summary>
    /// Decodes at the smallest JPEG DCT scale that still has at least the
    /// largest thumbnail's worth of pixels: much less memory and CPU for
    /// multi-megapixel originals.
    /// </summary>
    private static SKBitmap? Decode(SKCodec codec)
    {
        var info = codec.Info;
        if (codec.EncodedFormat == SKEncodedImageFormat.Jpeg)
        {
            var target = ThumbnailSizes.All.Max();
            foreach (var scale in new[] { 0.125f, 0.25f, 0.5f })
            {
                var dims = codec.GetScaledDimensions(scale);
                if (Math.Max(dims.Width, dims.Height) >= target)
                {
                    info = info.WithSize(dims.Width, dims.Height);
                    break;
                }
            }
        }

        var bitmap = new SKBitmap(info);
        var result = codec.GetPixels(info, bitmap.GetPixels());
        if (result is SKCodecResult.Success or SKCodecResult.IncompleteInput)
            return bitmap;

        bitmap.Dispose();
        return null;
    }

    /// <summary>Rotates/flips the decoded pixels so they are displayed upright (EXIF orientations 1-8).</summary>
    public static SKBitmap ApplyOrigin(SKBitmap src, SKEncodedOrigin origin)
    {
        if (origin == SKEncodedOrigin.TopLeft)
            return src.Copy();

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
        // Never upscale: a small original keeps its own size.
        var scale = Math.Min(1f, (float)size / longest);
        var width = Math.Max(1, (int)Math.Round(oriented.Width * scale));
        var height = Math.Max(1, (int)Math.Round(oriented.Height * scale));

        using var resized = scale >= 1f
            ? oriented.Copy()
            : oriented.Resize(oriented.Info.WithSize(width, height), new SKSamplingOptions(SKCubicResampler.Mitchell))
              ?? throw new PermanentPhotoException("Image could not be resized.");
        using var image = SKImage.FromBitmap(resized);
        using var data = image.Encode(SKEncodedImageFormat.Webp, WebpQuality)
            ?? throw new PermanentPhotoException("Thumbnail could not be encoded.");
        return data.ToArray();
    }
}
