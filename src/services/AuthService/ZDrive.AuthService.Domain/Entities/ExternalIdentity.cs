namespace ZDrive.AuthService.Domain.Entities;

/// <summary>
/// Maps an external identity provider's user (Microsoft Entra External ID)
/// to a local zDrive user. Keyed by (ProviderTenantId, ObjectId) — Entra's
/// tenant id (tid) and object id (oid) are immutable for the lifetime of the
/// account, unlike email (which a user can change) or the token's 'sub'
/// claim (which is scoped per application, not stable across app registrations).
/// </summary>
public sealed class ExternalIdentity
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string ProviderTenantId { get; set; }
    public required string ObjectId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public User User { get; set; } = null!;
}
