namespace ZDrive.AuthService.Infrastructure.Auth;

public sealed class JwtSettings
{
    public const string SectionName = "Jwt";

    // Empty by default. Resolved in AddInfrastructure: from configuration
    // (environment variables / Key Vault in production) or generated via
    // DevJwtKeyProvider in Development. Never commit key material to the repo.
    public string RsaPrivateKeyPem { get; set; } = "";
    public string RsaPublicKeyPem { get; set; } = "";
    public string Issuer { get; init; } = "zdrive";
    public string Audience { get; init; } = "zdrive-api";
    public int AccessTokenExpirationMinutes { get; init; } = 15;
    public int RefreshTokenExpirationDays { get; init; } = 30;
}
