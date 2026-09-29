namespace ZDrive.AuthService.Application.DTOs;

public sealed record UserDto(
    Guid Id,
    string Email,
    string DisplayName,
    string? AvatarUrl,
    string Role,
    Guid TenantId,
    DateTime CreatedAt,
    bool TwoFactorEnabled,
    // False for Entra-only accounts: no local password, so no 2FA setup.
    bool HasPassword);
