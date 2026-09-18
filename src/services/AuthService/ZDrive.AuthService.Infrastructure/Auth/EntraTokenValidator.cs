using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Infrastructure.Auth;

/// <summary>
/// Validates Entra External ID access tokens against that tenant's OpenID
/// Connect discovery document. The injected ConfigurationManager caches the
/// signing keys (refetched on its own rolling schedule), so a normal request
/// never blocks on a network round trip to Microsoft.
/// </summary>
public sealed class EntraTokenValidator : IEntraTokenValidator
{
    private readonly EntraOptions _options;
    private readonly IConfigurationManager<OpenIdConnectConfiguration> _configurationManager;
    private readonly JsonWebTokenHandler _handler = new();

    public EntraTokenValidator(
        IOptions<EntraOptions> options,
        IConfigurationManager<OpenIdConnectConfiguration> configurationManager)
    {
        _options = options.Value;
        _configurationManager = configurationManager;
    }

    public async Task<EntraIdentity> ValidateAsync(string accessToken, CancellationToken ct)
    {
        var configuration = await _configurationManager.GetConfigurationAsync(ct);

        var validationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = configuration.Issuer,
            ValidateAudience = true,
            ValidAudience = _options.Audience,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = configuration.SigningKeys
        };

        var result = await _handler.ValidateTokenAsync(accessToken, validationParameters);
        if (!result.IsValid)
            throw new ForbiddenException("The Entra access token could not be validated.");

        var claims = result.ClaimsIdentity;

        // Explicit checks beyond signature/issuer/audience/lifetime, per the
        // app's own trust requirements (not something TokenValidationParameters
        // expresses on its own).
        var tenantId = claims.FindFirst("tid")?.Value;
        if (tenantId is null || tenantId != _options.TenantId)
            throw new ForbiddenException("The Entra access token was not issued for this tenant.");

        var objectId = claims.FindFirst("oid")?.Value;
        if (string.IsNullOrEmpty(objectId))
            throw new ForbiddenException("The Entra access token is missing the required 'oid' claim.");

        var scopes = (claims.FindFirst("scp")?.Value ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (!scopes.Contains(_options.RequiredScope))
            throw new ForbiddenException("The Entra access token is missing the required scope.");

        // 'email' is an optional claim in Entra External ID — it must be
        // explicitly requested in the app registration's token configuration.
        // 'preferred_username' is a fallback but isn't guaranteed to be an email.
        var email = claims.FindFirst("email")?.Value ?? claims.FindFirst("preferred_username")?.Value;
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ForbiddenException(
                "The Entra access token has no email claim — configure the app registration to emit the optional 'email' claim.");
        }

        var displayName = claims.FindFirst("name")?.Value;

        return new EntraIdentity(tenantId, objectId, email, displayName);
    }
}
