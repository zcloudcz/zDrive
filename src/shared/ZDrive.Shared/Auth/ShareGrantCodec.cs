using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ZDrive.Shared.Auth;

/// <summary>
/// Shared encode/sign/verify core behind every "signed, stateless share
/// credential" type (ShareDownloadGrant, ShareUploadGrant, ShareUploadReceipt).
/// Wire format: base64url(json-payload).base64url(hmac).
///
/// Domain separation: the HMAC input is `purpose + payloadBytes`, not just
/// the payload bytes, so a valid download grant can never be replayed as an
/// upload grant (or vice versa) even though they share the same secret —
/// each type signs over a different byte string. ShareDownloadGrant keeps an
/// EMPTY purpose so its existing tokens/tests stay valid byte-for-byte after
/// this refactor.
/// </summary>
internal static class ShareGrantCodec
{
    public static string Create<TPayload>(string purpose, TPayload payload, byte[] key)
    {
        var payloadBytes = JsonSerializer.SerializeToUtf8Bytes(payload);
        var signature = Sign(purpose, payloadBytes, key);
        return $"{Base64UrlEncode(payloadBytes)}.{Base64UrlEncode(signature)}";
    }

    /// <summary>
    /// Never throws — a malformed, tampered, wrong-purpose, or expired token
    /// is just "not valid"; callers (public endpoints) answer 404 either way.
    /// </summary>
    public static bool TryValidate<TPayload>(
        string purpose, string? token, byte[] key, DateTimeOffset now,
        Func<TPayload, DateTimeOffset> expiresAtSelector, out TPayload payload)
    {
        payload = default!;

        if (string.IsNullOrEmpty(token))
            return false;

        var parts = token.Split('.', 2);
        if (parts.Length != 2)
            return false;

        byte[] payloadBytes;
        byte[] signature;
        try
        {
            payloadBytes = Base64UrlDecode(parts[0]);
            signature = Base64UrlDecode(parts[1]);
        }
        catch (FormatException)
        {
            return false;
        }

        // Verify the signature BEFORE the payload bytes are ever handed to
        // the JSON deserializer — an attacker-controlled payload should not
        // reach it unless it is provably ours. Constant-time compare so a
        // timing side-channel can't be used to forge a signature byte by byte.
        var expectedSignature = Sign(purpose, payloadBytes, key);
        if (!CryptographicOperations.FixedTimeEquals(signature, expectedSignature))
            return false;

        TPayload? candidate;
        try
        {
            candidate = JsonSerializer.Deserialize<TPayload>(payloadBytes);
        }
        catch (JsonException)
        {
            return false;
        }

        if (candidate is null || expiresAtSelector(candidate) <= now)
            return false;

        payload = candidate;
        return true;
    }

    private static byte[] Sign(string purpose, byte[] payloadBytes, byte[] key)
    {
        var purposeBytes = Encoding.UTF8.GetBytes(purpose);
        var input = new byte[purposeBytes.Length + payloadBytes.Length];
        Buffer.BlockCopy(purposeBytes, 0, input, 0, purposeBytes.Length);
        Buffer.BlockCopy(payloadBytes, 0, input, purposeBytes.Length, payloadBytes.Length);
        return HMACSHA256.HashData(key, input);
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
