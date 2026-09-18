using System.Security.Cryptography;
using System.Text.Json;

namespace ZDrive.Shared.Auth;

/// <summary>
/// Signed, stateless token that lets an anonymous public-share visitor
/// download blobs owned by someone else. StorageService derives the blob
/// path from the caller's own (tenantId, userId) — a link visitor has
/// neither, so FileService mints one of these addressed to the share
/// OWNER's ids and StorageService trusts it instead of a JWT.
///
/// HMAC-SHA256 with a separate shared secret, not the JWT RSA key: only
/// AuthService holds the RSA private key, and neither FileService nor
/// StorageService should gain the ability to mint auth tokens just to mint
/// download grants. A dedicated secret keeps this capability scoped to
/// exactly what it is.
/// </summary>
public static class ShareDownloadGrant
{
    public sealed record Payload(
        Guid TenantId,
        Guid OwnerUserId,
        Guid FileId,
        string ManifestHash,
        DateTimeOffset ExpiresAt);

    public static string Create(Payload payload, byte[] key)
    {
        var payloadBytes = JsonSerializer.SerializeToUtf8Bytes(payload);
        var signature = HMACSHA256.HashData(key, payloadBytes);
        return $"{Base64UrlEncode(payloadBytes)}.{Base64UrlEncode(signature)}";
    }

    /// <summary>
    /// Validates a grant string. Never throws — a malformed, tampered, or
    /// expired grant is just "not valid", and callers (public endpoints)
    /// answer 404 either way, so there is nothing gained by distinguishing
    /// parse errors from signature failures via exceptions.
    /// </summary>
    public static bool TryValidate(string? grant, byte[] key, DateTimeOffset now, out Payload payload)
    {
        payload = null!;

        if (string.IsNullOrEmpty(grant))
            return false;

        var parts = grant.Split('.', 2);
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
        var expectedSignature = HMACSHA256.HashData(key, payloadBytes);
        if (!CryptographicOperations.FixedTimeEquals(signature, expectedSignature))
            return false;

        Payload? candidate;
        try
        {
            candidate = JsonSerializer.Deserialize<Payload>(payloadBytes);
        }
        catch (JsonException)
        {
            return false;
        }

        if (candidate is null || candidate.ExpiresAt <= now)
            return false;

        payload = candidate;
        return true;
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
