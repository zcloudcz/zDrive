namespace ZDrive.AuthService.Application.DTOs;

public sealed record TwoFactorSetupDto(string Secret, string OtpAuthUri);

public sealed record RecoveryCodesDto(IReadOnlyList<string> RecoveryCodes);
