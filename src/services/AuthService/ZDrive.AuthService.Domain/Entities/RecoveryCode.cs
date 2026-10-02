namespace ZDrive.AuthService.Domain.Entities;

public sealed class RecoveryCode
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    // SHA-256(salt || normalized code), hex. The plain code is shown once at
    // enrollment; the per-code random salt defeats precomputed tables.
    public required string Salt { get; set; }
    public required string CodeHash { get; set; }
    public DateTime? UsedAt { get; set; }

    public User User { get; set; } = null!;
}
