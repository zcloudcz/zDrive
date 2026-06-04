namespace ZDrive.AuthService.Infrastructure.Auth;

public sealed class JwtSettings
{
    public const string SectionName = "Jwt";

    public required string RsaPrivateKeyPem { get; init; }
    public required string RsaPublicKeyPem { get; init; }
    public string Issuer { get; init; } = "zdrive";
    public string Audience { get; init; } = "zdrive-api";
    public int AccessTokenExpirationMinutes { get; init; } = 15;
    public int RefreshTokenExpirationDays { get; init; } = 30;
}
