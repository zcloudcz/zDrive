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
    // Empty purpose: this type predates the purpose-prefixed codec, so it
    // keeps signing over the bare payload bytes — existing grants and tests
    // stay valid byte-for-byte. New grant/receipt types below use a non-empty
    // purpose so they can never validate as a download grant, or as each other.
    private const string Purpose = "";

    public sealed record Payload(
        Guid TenantId,
        Guid OwnerUserId,
        Guid FileId,
        string ManifestHash,
        DateTimeOffset ExpiresAt);

    public static string Create(Payload payload, byte[] key) =>
        ShareGrantCodec.Create(Purpose, payload, key);

    /// <summary>
    /// Validates a grant string. Never throws — a malformed, tampered, or
    /// expired grant is just "not valid", and callers (public endpoints)
    /// answer 404 either way, so there is nothing gained by distinguishing
    /// parse errors from signature failures via exceptions.
    /// </summary>
    public static bool TryValidate(string? grant, byte[] key, DateTimeOffset now, out Payload payload) =>
        ShareGrantCodec.TryValidate(Purpose, grant, key, now, p => p.ExpiresAt, out payload);
}
