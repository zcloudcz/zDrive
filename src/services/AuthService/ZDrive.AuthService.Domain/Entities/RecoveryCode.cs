namespace ZDrive.AuthService.Domain.Entities;

public sealed class RecoveryCode
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    // SHA-256 of the normalized code; the plain code is shown once at enrollment.
    public required string CodeHash { get; set; }
    public DateTime? UsedAt { get; set; }

    public User User { get; set; } = null!;
}
