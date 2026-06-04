namespace ZDrive.AuthService.Application.DTOs;

public sealed record AuthTokenDto(
    string AccessToken,
    string RefreshToken,
    DateTime ExpiresAt);
