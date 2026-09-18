namespace ZDrive.Shared.Auth;

/// <summary>
/// Signed, stateless token StorageService issues when a shared upload
/// session completes, proving to FileService that these exact bytes
/// (manifestHash, sizeBytes) were actually written for this fileId — so
/// FileService can record the version without trusting the caller's own
/// claim of what was uploaded. Same key/codec as ShareDownloadGrant and
/// ShareUploadGrant, distinct purpose prefix (domain separation).
/// </summary>
public static class ShareUploadReceipt
{
    private const string Purpose = "zdrive-share-receipt-v1\n";

    public sealed record Payload(
        Guid FileId,
        string ManifestHash,
        long SizeBytes,
        DateTimeOffset ExpiresAt);

    public static string Create(Payload payload, byte[] key) =>
        ShareGrantCodec.Create(Purpose, payload, key);

    public static bool TryValidate(string? receipt, byte[] key, DateTimeOffset now, out Payload payload) =>
        ShareGrantCodec.TryValidate(Purpose, receipt, key, now, p => p.ExpiresAt, out payload);
}
