using System.Security.Claims;

namespace ZDrive.Shared.Auth;

public static class ClaimsHelper
{
    public static Guid GetUserId(this ClaimsPrincipal principal)
    {
        var value = principal.FindFirstValue(JwtConstants.UserIdClaim)
                   ?? throw new InvalidOperationException("User ID claim is missing.");
        return Guid.Parse(value);
    }

    public static Guid? GetTenantId(this ClaimsPrincipal principal)
    {
        var value = principal.FindFirstValue(JwtConstants.TenantIdClaim);
        return value is null ? null : Guid.Parse(value);
    }

    public static string GetRole(this ClaimsPrincipal principal)
    {
        return principal.FindFirstValue(JwtConstants.RoleClaim)
               ?? throw new InvalidOperationException("Role claim is missing.");
    }

    public static string GetDisplayName(this ClaimsPrincipal principal)
    {
        return principal.FindFirstValue(JwtConstants.DisplayNameClaim) ?? string.Empty;
    }
}
