namespace ZDrive.AuthService.Application.DTOs;

public sealed record TwoFactorSetupDto(string Secret, string OtpAuthUri);

/// <summary>
/// Result of turning 2FA on: the one-time recovery codes, plus a fresh token
/// pair for the current device (all other sessions were signed out).
/// </summary>
public sealed record RecoveryCodesDto(
    IReadOnlyList<string> RecoveryCodes,
    string AccessToken,
    string RefreshToken,
    DateTime ExpiresAt);
