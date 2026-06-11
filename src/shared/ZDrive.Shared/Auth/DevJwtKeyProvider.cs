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

    // Serializes generation within one process; cross-process races are tolerated
    // (worst case two services generate simultaneously and one pair wins — both
    // files are always written together, see GenerateAndStore).
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

        // Write private key first so a half-written state never has a public key
        // without its matching private key (services validate against the public one).
        File.WriteAllText(privatePath, privatePem);
        File.WriteAllText(publicPath, publicPem);

        return (privatePem, publicPem);
    }
}
