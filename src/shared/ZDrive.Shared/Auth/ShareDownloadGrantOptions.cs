namespace ZDrive.Shared.Auth;

/// <summary>
/// Options for <see cref="ShareDownloadGrant"/> signing/validation, bound
/// from the "Sharing" configuration section in both FileService (mints
/// grants) and StorageService (validates them) — they must agree on the key.
///
/// A missing or too-short key means the public-download-grant feature fails
/// CLOSED (the endpoints that use it answer 404) rather than throwing at
/// startup: production does not have this key configured yet, and every
/// service still has to start.
/// </summary>
public sealed class ShareDownloadGrantOptions
{
    public const string SectionName = "Sharing";

    /// <summary>Base64-encoded HMAC key. Must decode to at least 32 bytes.</summary>
    public string? DownloadGrantKey { get; set; }

    /// <summary>
    /// Decodes <see cref="DownloadGrantKey"/>, or returns false if it is
    /// missing, not valid base64, or shorter than 32 bytes.
    /// </summary>
    public bool TryGetKey(out byte[] key)
    {
        key = [];

        if (string.IsNullOrWhiteSpace(DownloadGrantKey))
            return false;

        try
        {
            var decoded = Convert.FromBase64String(DownloadGrantKey);
            if (decoded.Length < 32)
                return false;

            key = decoded;
            return true;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}
