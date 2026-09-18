namespace ZDrive.AuthService.Application.Interfaces;

/// <summary>
/// Validates an Entra External ID access token and extracts the caller's
/// federated identity. The real implementation fetches signing keys over the
/// network (OpenID Connect discovery); this seam lets tests substitute a fake.
/// </summary>
public interface IEntraTokenValidator
{
    Task<EntraIdentity> ValidateAsync(string accessToken, CancellationToken ct);
}

public sealed record EntraIdentity(string TenantId, string ObjectId, string Email, string? DisplayName);
