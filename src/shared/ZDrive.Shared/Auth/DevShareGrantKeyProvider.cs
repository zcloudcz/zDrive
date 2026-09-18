using System.Security.Cryptography;

namespace ZDrive.Shared.Auth;

/// <summary>
/// Provides a development-only HMAC key for ShareDownloadGrant, the same way
/// DevJwtKeyProvider provides a dev JWT signing key: never committed, each
/// developer machine generates it on first use, and every locally-running
/// service reads the same file — FileService (which signs a grant) and
/// StorageService (which validates one) agree on a key with nothing in git.
///
/// Production must NOT rely on this class — see DevJwtKeyProvider's own
/// note; callers are expected to gate the fallback on
/// <c>IHostEnvironment.IsDevelopment()</c>. Outside Development, an empty
/// <c>Sharing:DownloadGrantKey</c> just means the feature is off
/// (ShareDownloadGrantOptions.TryGetKey fails closed) — no fallback here.
/// </summary>
public static class DevShareGrantKeyProvider
{
    private const string KeyFileName = "share-grant.key";

    // Serializes generation within one process. Cross-process races are
    // resolved the same way as DevJwtKeyProvider: a move-without-overwrite
    // on the key file picks a single winner; losers discard their bytes and
    // re-read the winner's file.
    private static readonly object Lock = new();

    /// <summary>
    /// Returns the base64-encoded dev HMAC key (ready to assign to
    /// ShareDownloadGrantOptions.DownloadGrantKey), generating and
    /// persisting it on first use. Shares DevJwtKeyProvider's key directory
    /// (and its ZDRIVE_DEV_KEY_DIR override), so nothing new needs to ride
    /// along in docker-compose's volume mount for it.
    /// </summary>
    public static string GetOrCreateKey()
    {
        lock (Lock)
        {
            var dir = GetKeyDirectory();
            var path = Path.Combine(dir, KeyFileName);

            if (File.Exists(path))
            {
                return File.ReadAllText(path);
            }

            return GenerateAndStore(dir, path);
        }
    }

    private static string GetKeyDirectory()
    {
        var overrideDir = Environment.GetEnvironmentVariable(DevJwtKeyProvider.KeyDirEnvVar);
        if (!string.IsNullOrWhiteSpace(overrideDir))
        {
            return overrideDir;
        }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(home, ".zdrive", "dev-keys");
    }

    private static string GenerateAndStore(string dir, string path)
    {
        Directory.CreateDirectory(dir);

        var keyBase64 = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

        // Write to a temp file first so no other process can ever read a
        // half-written key, then move into place. The move-without-overwrite
        // decides a single winner when several services generate at the same
        // time (e.g. parallel first start on a clean machine).
        var tempPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(tempPath, keyBase64);

        try
        {
            File.Move(tempPath, path); // throws if another process won
        }
        catch (IOException)
        {
            File.Delete(tempPath);
            return ReadExisting(path);
        }

        return keyBase64;
    }

    private static string ReadExisting(string path)
    {
        // The winning process may still be mid-move — wait briefly for the
        // file to become readable.
        for (var attempt = 0; attempt < 50; attempt++)
        {
            if (File.Exists(path))
            {
                try
                {
                    return File.ReadAllText(path);
                }
                catch (IOException)
                {
                    // File mid-move; fall through to retry.
                }
            }

            Thread.Sleep(100);
        }

        throw new InvalidOperationException(
            $"Timed out waiting for the dev share-grant key in '{Path.GetDirectoryName(path)}'.");
    }
}
