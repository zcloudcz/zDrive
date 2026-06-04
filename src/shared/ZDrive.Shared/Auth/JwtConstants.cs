namespace ZDrive.Shared.Auth;

public static class JwtConstants
{
    public const string Issuer = "zdrive";
    public const string Audience = "zdrive-api";

    // Custom claim types
    public const string TenantIdClaim = "tenant_id";
    public const string UserIdClaim = "sub";
    public const string RoleClaim = "role";
    public const string DisplayNameClaim = "display_name";
}
