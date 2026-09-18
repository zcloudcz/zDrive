namespace ZDrive.Shared.Auth;

/// <summary>
/// Signed, stateless token that lets an anonymous public-share visitor with
/// Write permission upload blobs owned by someone else, the upload-direction
/// twin of <see cref="ShareDownloadGrant"/>. Same key, same wire format, but
/// a distinct purpose prefix (domain separation — see ShareGrantCodec) so an
/// upload grant can never be replayed where a download grant is expected.
/// </summary>
public static class ShareUploadGrant
{
    private const string Purpose = "zdrive-share-upload-v1\n";

    public sealed record Payload(
        Guid TenantId,
        Guid OwnerUserId,
        Guid FileId,
        long MaxBytes,
        DateTimeOffset ExpiresAt,
        // Owner's quota headroom at mint time (limit - used, never negative).
        // StorageService has no way to see FileService's quota on its own —
        // this bounds how much a Write-link holder can push into promoted,
        // unreceipted blob storage across a burst of grants. See
        // InitUploadCommandHandler's 24h in-flight budget check.
        long QuotaRemainingBytes);

    public static string Create(Payload payload, byte[] key) =>
        ShareGrantCodec.Create(Purpose, payload, key);

    public static bool TryValidate(string? grant, byte[] key, DateTimeOffset now, out Payload payload) =>
        ShareGrantCodec.TryValidate(Purpose, grant, key, now, p => p.ExpiresAt, out payload);
}
