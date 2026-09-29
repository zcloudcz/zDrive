using ZDrive.AuthService.Domain.Enums;

namespace ZDrive.AuthService.Domain.Entities;

public sealed class User
{
    public Guid Id { get; set; }
    public required string Email { get; set; }
    // Null for Entra-only accounts — there is no local password to verify against.
    public required string? PasswordHash { get; set; }
    public required string DisplayName { get; set; }
    public string? AvatarUrl { get; set; }
    public Role Role { get; set; } = Role.Owner;
    public Guid TenantId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastLoginAt { get; set; }

    // TOTP 2FA. The secret is stored protected (ASP.NET Core Data Protection),
    // never as plain text. A secret with TwoFactorEnabledAt == null is a
    // pending enrollment that login ignores until it is confirmed with a code.
    public string? TwoFactorSecretProtected { get; set; }
    public DateTime? TwoFactorEnabledAt { get; set; }
    // When the pending secret was issued; setup returns the same pending
    // secret for a short while instead of replacing it on every call.
    public DateTime? TwoFactorSecretCreatedAt { get; set; }

    public bool TwoFactorEnabled => TwoFactorEnabledAt is not null;

    // Navigation
    public Tenant Tenant { get; set; } = null!;
    public ICollection<RefreshToken> RefreshTokens { get; set; } = [];
    public ICollection<RecoveryCode> RecoveryCodes { get; set; } = [];
}
