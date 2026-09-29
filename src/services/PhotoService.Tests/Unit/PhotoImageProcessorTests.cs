using FluentAssertions;
using SkiaSharp;
using Xunit;
using ZDrive.PhotoService.Application.Common;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.PhotoService.Infrastructure.Ingest;

namespace ZDrive.PhotoService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class PhotoImageProcessorTests
{
    private readonly SkiaPhotoImageProcessor _processor = new();

    [Fact]
    public void Process_JpegWithFullExif_ExtractsMetadataAndBothThumbnails()
    {
        var jpeg = TestImages.Jpeg(300, 150, new(
            Orientation: 1, DateTimeOriginal: "2020:01:02 03:04:05", Gps: (-33.8688, 151.2093), Make: "Acme", Model: "X1"));

        var result = _processor.Process(jpeg);

        result.TakenAtUtc.Should().Be(new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc), "no offset tag: wall clock is treated as UTC");
        result.Lat.Should().BeApproximately(-33.8688, 0.001, "southern hemisphere is negative");
        result.Lng.Should().BeApproximately(151.2093, 0.001);
        (result.CameraMake, result.CameraModel).Should().Be(("Acme", "X1"));
        (result.Width, result.Height).Should().Be((300, 150));
        result.Thumbnails.Keys.Should().BeEquivalentTo(ThumbnailSizes.All);
        Size(result.Thumbnails[256]).Should().Be((256, 128));
        Size(result.Thumbnails[1024]).Should().Be((300, 150), "no upscaling");
    }

    [Fact]
    public void Process_JpegWithoutExif_ReturnsDimensionsAndNoDate()
    {
        var result = _processor.Process(TestImages.Jpeg(64, 48));

        result.TakenAtUtc.Should().BeNull();
        result.Lat.Should().BeNull();
        (result.Width, result.Height).Should().Be((64, 48));
        result.Orientation.Should().Be(1);
    }

    [Fact]
    public void Process_LargeJpeg_ThumbnailsStillHaveTargetSize()
    {
        // Exercises the scaled-decode path (source much larger than 1024 px).
        var result = _processor.Process(TestImages.Jpeg(4000, 3000));

        (result.Width, result.Height).Should().Be((4000, 3000), "reported dimensions are the original's, not the scaled decode's");
        Size(result.Thumbnails[1024]).Should().Be((1024, 768));
        Size(result.Thumbnails[256]).Should().Be((256, 192));
    }

    [Fact]
    public void Process_Garbage_ThrowsPermanent()
    {
        var act = () => _processor.Process(new byte[200]);

        act.Should().Throw<PermanentPhotoException>();
    }

    [Fact]
    public void Process_HeicHeader_ReturnsMetadataOnlyWithoutThumbnails()
    {
        var result = _processor.Process(TestImages.HeicHeaderOnly());

        result.Thumbnails.Should().BeEmpty("Skia cannot decode HEIC on Linux");
    }

    [Theory]
    [InlineData("+02:00", 10, 0)]
    [InlineData("-05:30", 17, 30)]
    [InlineData(null, 12, 0)]
    [InlineData("garbage", 12, 0)]
    public void ToUtc_AppliesOffsetTagWhenPresentAndValid(string? offset, int expectedHour, int expectedMinute)
    {
        var utc = SkiaPhotoImageProcessor.ToUtc(new DateTime(2021, 7, 4, 12, 0, 0), offset);

        (utc.Hour, utc.Minute).Should().Be((expectedHour, expectedMinute));
        utc.Kind.Should().Be(DateTimeKind.Utc);
    }

    /// <summary>
    /// EXIF orientation 1-8: where does the source's top-left pixel (red) land?
    /// Source is 3x2, so 90-degree origins produce a 2x3 result.
    /// </summary>
    [Theory]
    [InlineData(SKEncodedOrigin.TopLeft, 3, 2, 0, 0)]
    [InlineData(SKEncodedOrigin.TopRight, 3, 2, 2, 0)]
    [InlineData(SKEncodedOrigin.BottomRight, 3, 2, 2, 1)]
    [InlineData(SKEncodedOrigin.BottomLeft, 3, 2, 0, 1)]
    [InlineData(SKEncodedOrigin.LeftTop, 2, 3, 0, 0)]
    [InlineData(SKEncodedOrigin.RightTop, 2, 3, 1, 0)]
    [InlineData(SKEncodedOrigin.RightBottom, 2, 3, 1, 2)]
    [InlineData(SKEncodedOrigin.LeftBottom, 2, 3, 0, 2)]
    public void ApplyOrigin_MovesTopLeftPixelWhereExifSaysItBelongs(
        SKEncodedOrigin origin, int width, int height, int redX, int redY)
    {
        using var source = new SKBitmap(3, 2);
        source.Erase(SKColors.Blue);
        source.SetPixel(0, 0, SKColors.Red);

        using var result = SkiaPhotoImageProcessor.ApplyOrigin(source, origin);

        (result.Width, result.Height).Should().Be((width, height));
        result.GetPixel(redX, redY).Should().Be(SKColors.Red);
        var reds = Enumerable.Range(0, width).SelectMany(x => Enumerable.Range(0, height).Select(y => result.GetPixel(x, y)))
            .Count(c => c == SKColors.Red);
        reds.Should().Be(1, "orientation must only move pixels, never blend them");
    }

    private static (int, int) Size(byte[] webp)
    {
        using var bitmap = SKBitmap.Decode(webp);
        return (bitmap.Width, bitmap.Height);
    }
}

[Trait("Category", "Unit")]
public sealed class PhotoNamingRulesTests
{
    [Theory]
    [InlineData("a.jpg", null, true)]
    [InlineData("a.JPEG", null, true)]
    [InlineData("a.png", null, true)]
    [InlineData("a.heic", null, true)]
    [InlineData("a.heif", null, true)]
    [InlineData("a.webp", null, true)]
    [InlineData("a", "image/gif", true)]
    [InlineData("a.txt", "text/plain", false)]
    [InlineData("a.pdf", null, false)]
    [InlineData("noext", "application/octet-stream", false)]
    [InlineData("a.jpg", "application/octet-stream", true)]
    public void IsImage_ByMimeThenExtension(string name, string? mime, bool expected) =>
        ImageFileTypes.IsImage(name, mime).Should().Be(expected);

    [Theory]
    [InlineData("IMG_20231225_143022.jpg", 2023, 12, 25, 14, 30, 22)]
    [InlineData("2023-12-25_14-30-22.jpg", 2023, 12, 25, 14, 30, 22)]
    public void FileNameDateParser_RecognisesCameraNames(string name, int y, int mo, int d, int h, int mi, int s) =>
        FileNameDateParser.TryParse(name).Should().Be(new DateTime(y, mo, d, h, mi, s, DateTimeKind.Utc));

    [Fact]
    public void FileNameDateParser_NoDateInName_ReturnsNull() =>
        FileNameDateParser.TryParse("holiday.jpg").Should().BeNull();
}
