using System.Text;
using SkiaSharp;

namespace ZDrive.PhotoService.Tests;

/// <summary>Generates JPEGs with hand-built EXIF so no binary fixtures live in the repo.</summary>
public static class TestImages
{
    public sealed record ExifSpec(
        int? Orientation = null,
        string? DateTimeOriginal = null,   // "2021:07:04 12:34:56"
        string? OffsetTimeOriginal = null, // "+02:00"
        (double Lat, double Lng)? Gps = null,
        string? Make = null,
        string? Model = null);

    /// <summary>Red rectangle with a blue left third, so orientation errors are visible.</summary>
    public static byte[] Jpeg(int width, int height, ExifSpec? exif = null)
    {
        using var bitmap = new SKBitmap(width, height);
        using (var canvas = new SKCanvas(bitmap))
        {
            canvas.Clear(SKColors.Red);
            using var paint = new SKPaint { Color = SKColors.Blue };
            canvas.DrawRect(0, 0, width / 3f, height, paint);
        }

        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Jpeg, 90);
        var jpeg = data.ToArray();
        if (exif is null)
            return jpeg;

        var app1 = BuildApp1(exif);
        return jpeg.Take(2).Concat(app1).Concat(jpeg.Skip(2)).ToArray(); // SOI, APP1, rest
    }

    public static byte[] Png(int width, int height)
    {
        using var bitmap = new SKBitmap(width, height);
        using (var canvas = new SKCanvas(bitmap)) canvas.Clear(SKColors.Green);
        using var image = SKImage.FromBitmap(bitmap);
        return image.Encode(SKEncodedImageFormat.Png, 100).ToArray();
    }

    /// <summary>
    /// A tiny (~70 byte) PNG whose IHDR declares <paramref name="width"/> x
    /// <paramref name="height"/>: what a decompression bomb looks like. Header
    /// and chunk CRCs are valid so Skia's codec accepts it up to the pixel data.
    /// </summary>
    public static byte[] PngDeclaring(int width, int height)
    {
        static byte[] Be(int v) => [(byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v];
        static byte[] Chunk(string type, byte[] data)
        {
            var typed = Encoding.ASCII.GetBytes(type).Concat(data).ToArray();
            var crc = 0xFFFFFFFFu;
            foreach (var b in typed)
            {
                crc ^= b;
                for (var i = 0; i < 8; i++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
            }
            return [.. Be(data.Length), .. typed, .. Be((int)~crc)];
        }

        byte[] ihdr = [.. Be(width), .. Be(height), 8, 2, 0, 0, 0]; // 8-bit RGB
        byte[] zlibEmpty = [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01];
        return [0x89, (byte)'P', (byte)'N', (byte)'G', 0x0D, 0x0A, 0x1A, 0x0A,
                .. Chunk("IHDR", ihdr), .. Chunk("IDAT", zlibEmpty), .. Chunk("IEND", [])];
    }

    /// <summary>Just an ISO-BMFF "ftyp heic" header: recognised as HEIC, undecodable by Skia on Linux.</summary>
    public static byte[] HeicHeaderOnly() =>
        [0, 0, 0, 24, (byte)'f', (byte)'t', (byte)'y', (byte)'p', (byte)'h', (byte)'e', (byte)'i', (byte)'c',
         0, 0, 0, 0, (byte)'m', (byte)'i', (byte)'f', (byte)'1', (byte)'h', (byte)'e', (byte)'i', (byte)'c'];

    private sealed record Entry(ushort Tag, ushort Type, uint Count, byte[] Value);

    private static byte[] BuildApp1(ExifSpec spec)
    {
        static byte[] Ascii(string s) => Encoding.ASCII.GetBytes(s + "\0");
        static byte[] Short(int v) => [(byte)v, (byte)(v >> 8), 0, 0];
        static byte[] Rational(uint num, uint den) => [.. BitConverter.GetBytes(num), .. BitConverter.GetBytes(den)];

        var ifd0 = new List<Entry>();
        if (spec.Make is not null) ifd0.Add(new(0x10F, 2, (uint)spec.Make.Length + 1, Ascii(spec.Make)));
        if (spec.Model is not null) ifd0.Add(new(0x110, 2, (uint)spec.Model.Length + 1, Ascii(spec.Model)));
        if (spec.Orientation is { } o) ifd0.Add(new(0x112, 3, 1, Short(o)));

        var exifEntries = new List<Entry>();
        if (spec.DateTimeOriginal is not null)
            exifEntries.Add(new(0x9003, 2, (uint)spec.DateTimeOriginal.Length + 1, Ascii(spec.DateTimeOriginal)));
        if (spec.OffsetTimeOriginal is not null)
            exifEntries.Add(new(0x9011, 2, (uint)spec.OffsetTimeOriginal.Length + 1, Ascii(spec.OffsetTimeOriginal)));

        var gpsEntries = new List<Entry>();
        if (spec.Gps is { } gps)
        {
            static byte[] Dms(double deg)
            {
                deg = Math.Abs(deg);
                var d = (uint)Math.Floor(deg);
                var m = (uint)Math.Floor((deg - d) * 60);
                var s = (deg - d - m / 60.0) * 3600;
                return [.. Rational(d, 1), .. Rational(m, 1), .. Rational((uint)Math.Round(s * 10000), 10000)];
            }
            gpsEntries.Add(new(1, 2, 2, [(byte)(gps.Lat >= 0 ? 'N' : 'S'), 0, 0, 0]));
            gpsEntries.Add(new(2, 5, 3, Dms(gps.Lat)));
            gpsEntries.Add(new(3, 2, 2, [(byte)(gps.Lng >= 0 ? 'E' : 'W'), 0, 0, 0]));
            gpsEntries.Add(new(4, 5, 3, Dms(gps.Lng)));
        }

        // Pointer entries are fixed-size (4 byte value), so IFD sizes can be
        // computed before offsets are known.
        if (exifEntries.Count > 0) ifd0.Add(new(0x8769, 4, 1, new byte[4]));
        if (gpsEntries.Count > 0) ifd0.Add(new(0x8825, 4, 1, new byte[4]));

        static int IfdSize(List<Entry> e) =>
            2 + 12 * e.Count + 4 + e.Where(x => x.Value.Length > 4).Sum(x => x.Value.Length + (x.Value.Length & 1));

        var ifd0Offset = 8;
        var exifOffset = ifd0Offset + IfdSize(ifd0);
        var gpsOffset = exifOffset + (exifEntries.Count > 0 ? IfdSize(exifEntries) : 0);
        for (var i = 0; i < ifd0.Count; i++)
        {
            if (ifd0[i].Tag == 0x8769) ifd0[i] = ifd0[i] with { Value = BitConverter.GetBytes((uint)exifOffset) };
            if (ifd0[i].Tag == 0x8825) ifd0[i] = ifd0[i] with { Value = BitConverter.GetBytes((uint)gpsOffset) };
        }

        using var tiff = new MemoryStream();
        tiff.Write("II"u8);
        tiff.Write(BitConverter.GetBytes((ushort)42));
        tiff.Write(BitConverter.GetBytes(8u));
        WriteIfd(tiff, ifd0, ifd0Offset);
        if (exifEntries.Count > 0) WriteIfd(tiff, exifEntries, exifOffset);
        if (gpsEntries.Count > 0) WriteIfd(tiff, gpsEntries, gpsOffset);

        var body = new MemoryStream();
        body.Write("Exif\0\0"u8);
        body.Write(tiff.ToArray());
        var length = (int)body.Length + 2;
        return [0xFF, 0xE1, (byte)(length >> 8), (byte)(length & 0xFF), .. body.ToArray()];
    }

    private static void WriteIfd(Stream output, List<Entry> entries, int ifdOffset)
    {
        entries = entries.OrderBy(e => e.Tag).ToList();
        var dataOffset = ifdOffset + 2 + 12 * entries.Count + 4;
        var data = new MemoryStream();

        output.Write(BitConverter.GetBytes((ushort)entries.Count));
        foreach (var e in entries)
        {
            output.Write(BitConverter.GetBytes(e.Tag));
            output.Write(BitConverter.GetBytes(e.Type));
            output.Write(BitConverter.GetBytes(e.Count));
            if (e.Value.Length <= 4)
            {
                output.Write(e.Value);
                for (var i = e.Value.Length; i < 4; i++) output.WriteByte(0);
            }
            else
            {
                output.Write(BitConverter.GetBytes((uint)(dataOffset + data.Length)));
                data.Write(e.Value);
                if ((e.Value.Length & 1) == 1) data.WriteByte(0);
            }
        }

        output.Write(BitConverter.GetBytes(0u)); // no next IFD
        output.Write(data.ToArray());
    }
}
