namespace ZDrive.AuthService.Application.Auth;

public sealed class EntraOptions
{
    public const string SectionName = "Entra";

    // Off by default — the /auth/entra endpoint 404s until a deployment
    // configures an actual Entra External ID app registration (see
    // AddInfrastructure, which fails startup if Enabled is true but the
    // rest of the section is incomplete).
    public bool Enabled { get; init; }
    public string TenantId { get; init; } = "";
    public string Audience { get; init; } = "";
    public string RequiredScope { get; init; } = "";
}
