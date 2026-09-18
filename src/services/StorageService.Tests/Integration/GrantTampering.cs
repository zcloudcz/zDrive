namespace ZDrive.StorageService.Tests.Integration;

/// <summary>
/// Tampers a signed grant/receipt token (base64url(payload).base64url(hmac))
/// so it fails signature verification. Flipping the LAST base64url character
/// of a 32-byte HMAC-SHA256 signature is NOT reliable: that character only
/// encodes the low 2 bits of the last byte after padding, and base64url
/// decoding of a well-formed 4-symbol group can discard bits that never
/// round-trip back into the byte array — the token can come out byte-for-byte
/// identical to the original and still validate. XOR-ing a bit into the
/// FIRST byte of the decoded signature always changes the byte array itself,
/// so it is guaranteed to break verification regardless of padding.
/// </summary>
internal static class GrantTampering
{
    public static string FlipSignatureBit(string token)
    {
        var parts = token.Split('.', 2);
        var signatureBytes = Base64UrlDecode(parts[1]);
        signatureBytes[0] ^= 0x01;
        return $"{parts[0]}.{Base64UrlEncode(signatureBytes)}";
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = padded.PadRight(padded.Length + ((4 - (padded.Length % 4)) % 4), '=');
        return Convert.FromBase64String(padded);
    }
}
