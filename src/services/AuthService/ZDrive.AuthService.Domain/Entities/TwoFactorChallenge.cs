namespace ZDrive.AuthService.Domain.Entities;

/// <summary>
/// Short-lived, single-use proof that a password was verified for a 2FA
/// account. Kept in the database (not a signed JWT) so it can be consumed.
/// </summary>
public sealed class TwoFactorChallenge
{
    public const int MaxFailedAttempts = 5;

    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    // SHA-256 of the token handed to the client.
    public required string TokenHash { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
    public DateTime? UsedAt { get; set; }
    public int FailedAttempts { get; set; }

    public bool IsUsable => UsedAt is null && FailedAttempts < MaxFailedAttempts && DateTime.UtcNow < ExpiresAt;

    public User User { get; set; } = null!;
}
