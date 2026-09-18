using System.Globalization;
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

    /// <summary>
    /// Per-user storage quota override carried on the JWT. Absent for most
    /// users today (subscription plans will start setting it later) — a null
    /// return means "fall back to the configured default", not "unlimited".
    /// A garbage claim value also falls back to the default instead of
    /// throwing a FormatException that would 500 every request from that
    /// user. Zero or negative is returned as-is — both already mean
    /// "everything refused" once it reaches EnsureCanStoreAsync, not
    /// "unlimited", so there is nothing to guard against here.
    /// </summary>
    public static long? GetQuotaBytes(this ClaimsPrincipal principal)
    {
        var value = principal.FindFirstValue(JwtConstants.QuotaBytesClaim);
        if (value is null)
            return null;
        return long.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var quotaBytes)
            ? quotaBytes
            : null;
    }
}
