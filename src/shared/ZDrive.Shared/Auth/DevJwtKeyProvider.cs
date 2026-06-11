using System.Security.Cryptography;

namespace ZDrive.Shared.Auth;

/// <summary>
/// Provides a development-only RSA key pair for JWT signing/validation.
///
/// Why this exists: committing a private key to the repository (even a "dev" one)
/// would let anyone with repo access forge tokens. Instead, each developer machine
/// generates its own key pair on first run and stores it outside the repository.
/// All locally running services read the same files, so tokens issued by
/// AuthService validate everywhere.
///
/// Production deployments must NOT rely on this class — they supply key material
/// via environment variables / Azure Key Vault. Callers are expected to gate the
/// fallback on <c>IHostEnvironment.IsDevelopment()</c>.
/// </summary>
public static class DevJwtKeyProvider
{
    /// <summary>Environment variable that overrides the default key directory.</summary>
    public const string KeyDirEnvVar = "ZDRIVE_DEV_KEY_DIR";

    private const string PrivateKeyFileName = "jwt-signing.key.pem";
    private const string PublicKeyFileName = "jwt-signing.pub.pem";

    // Serializes generation within one process. Cross-process races are resolved
    // in GenerateAndStore: a move-without-overwrite on the private key file picks
    // a single winner; losers discard their pair and read the winner's files.
    private static readonly object Lock = new();

    /// <summary>
    /// Returns the PEM-encoded dev key pair, generating and persisting it on first use.
    /// </summary>
    public static (string PrivateKeyPem, string PublicKeyPem) GetOrCreateKeyPair()
    {
        lock (Lock)
        {
            var dir = GetKeyDirectory();
            var privatePath = Path.Combine(dir, PrivateKeyFileName);
            var publicPath = Path.Combine(dir, PublicKeyFileName);

            if (File.Exists(privatePath) && File.Exists(publicPath))
            {
                return (File.ReadAllText(privatePath), File.ReadAllText(publicPath));
            }

            return GenerateAndStore(dir, privatePath, publicPath);
        }
    }

    private static string GetKeyDirectory()
    {
        var overrideDir = Environment.GetEnvironmentVariable(KeyDirEnvVar);
        if (!string.IsNullOrWhiteSpace(overrideDir))
        {
            return overrideDir;
        }

        // User profile keeps the keys per-developer and out of any repository.
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(home, ".zdrive", "dev-keys");
    }

    private static (string PrivateKeyPem, string PublicKeyPem) GenerateAndStore(
        string dir, string privatePath, string publicPath)
    {
        Directory.CreateDirectory(dir);

        using var rsa = RSA.Create(2048);
        var privatePem = rsa.ExportRSAPrivateKeyPem();
        var publicPem = rsa.ExportSubjectPublicKeyInfoPem();

        // Write the pair to temp files first so no other process can ever read a
        // half-written PEM, then move into place. The move-without-overwrite on
        // the private key decides a single winner when several services generate
        // at the same time (e.g. parallel first start on a clean machine).
        var tempSuffix = "." + Guid.NewGuid().ToString("N") + ".tmp";
        var tempPrivate = privatePath + tempSuffix;
        var tempPublic = publicPath + tempSuffix;
        File.WriteAllText(tempPrivate, privatePem);
        File.WriteAllText(tempPublic, publicPem);

        try
        {
            File.Move(tempPrivate, privatePath); // throws if another process won
        }
        catch (IOException)
        {
            File.Delete(tempPrivate);
            File.Delete(tempPublic);
            return ReadExistingPair(privatePath, publicPath);
        }

        File.Move(tempPublic, publicPath, overwrite: true);
        return (privatePem, publicPem);
    }

    private static (string PrivateKeyPem, string PublicKeyPem) ReadExistingPair(
        string privatePath, string publicPath)
    {
        // The winning process may still be moving its public key into place —
        // wait briefly for both files to become readable.
        for (var attempt = 0; attempt < 50; attempt++)
        {
            if (File.Exists(privatePath) && File.Exists(publicPath))
            {
                try
                {
                    return (File.ReadAllText(privatePath), File.ReadAllText(publicPath));
                }
                catch (IOException)
                {
                    // File mid-move; fall through to retry.
                }
            }

            Thread.Sleep(100);
        }

        throw new InvalidOperationException(
            $"Timed out waiting for the dev JWT key pair in '{Path.GetDirectoryName(privatePath)}'.");
    }
}
