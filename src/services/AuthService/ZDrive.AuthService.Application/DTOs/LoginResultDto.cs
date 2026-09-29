namespace ZDrive.AuthService.Application.DTOs;

/// <summary>
/// Login response. Without 2FA the token fields are set exactly as in
/// <see cref="AuthTokenDto"/>; with 2FA they are null and
/// <see cref="ChallengeToken"/> must be completed via POST /auth/login/2fa.
/// </summary>
public sealed record LoginResultDto(
    string? AccessToken,
    string? RefreshToken,
    DateTime? ExpiresAt,
    bool TwoFactorRequired,
    string? ChallengeToken)
{
    public static LoginResultDto FromTokens(AuthTokenDto tokens) =>
        new(tokens.AccessToken, tokens.RefreshToken, tokens.ExpiresAt, false, null);

    public static LoginResultDto Challenge(string challengeToken) =>
        new(null, null, null, true, challengeToken);
}
