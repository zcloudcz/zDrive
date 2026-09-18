namespace ZDrive.AuthService.Domain.Entities;

public sealed class RefreshToken
{
    public Guid Id { get; set; }
    public required string Token { get; set; }
    public Guid UserId { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? RevokedAt { get; set; }
    public string? ReplacedByToken { get; set; }

    // Null for the legacy password flow (plain rotating 30-day expiry, unchanged).
    // Set by the Entra exchange to cap a federated session at 24h so it can't stay
    // renewable indefinitely after access is revoked on the Entra side.
    public DateTime? AbsoluteExpiresAt { get; set; }

    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;
    public bool IsRevoked => RevokedAt is not null;
    public bool IsActive => !IsRevoked && !IsExpired;

    // Navigation
    public User User { get; set; } = null!;
}
