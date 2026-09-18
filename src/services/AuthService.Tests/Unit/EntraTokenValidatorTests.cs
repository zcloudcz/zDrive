using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using Xunit;
using ZDrive.AuthService.Infrastructure.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class EntraTokenValidatorTests
{
    private const string Issuer = "https://test-tenant.ciamlogin.com/test-tenant/v2.0";
    private const string Audience = "test-audience";
    private const string TenantId = "test-tenant";
    private const string RequiredScope = "access_as_user";

    private static readonly RSA SigningKey = RSA.Create(2048);
    private static readonly RSA OtherKey = RSA.Create(2048);

    private static EntraOptions CreateOptions() => new()
    {
        Enabled = true,
        TenantId = TenantId,
        Audience = Audience,
        RequiredScope = RequiredScope
    };

    private static OpenIdConnectConfiguration CreateConfiguration()
    {
        var config = new OpenIdConnectConfiguration { Issuer = Issuer };
        config.SigningKeys.Add(new RsaSecurityKey(SigningKey));
        return config;
    }

    private static EntraTokenValidator CreateValidator() =>
        new(Options.Create(CreateOptions()), new StaticConfigurationManager(CreateConfiguration()));

    private static string CreateToken(
        RSA? signingKey = null,
        string? issuer = null,
        string? audience = null,
        string? tid = TenantId,
        string? oid = "object-1",
        string? scp = RequiredScope,
        string? email = "user@example.com",
        DateTime? expires = null)
    {
        signingKey ??= SigningKey;

        var claims = new Dictionary<string, object>();
        if (tid is not null) claims["tid"] = tid;
        if (oid is not null) claims["oid"] = oid;
        if (scp is not null) claims["scp"] = scp;
        if (email is not null) claims["email"] = email;
        claims["name"] = "Test User";

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = issuer ?? Issuer,
            Audience = audience ?? Audience,
            Claims = claims,
            Expires = expires ?? DateTime.UtcNow.AddMinutes(15),
            SigningCredentials = new SigningCredentials(new RsaSecurityKey(signingKey), SecurityAlgorithms.RsaSha256)
        };

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }

    [Fact]
    public async Task ValidateAsync_ValidToken_ReturnsIdentity()
    {
        var validator = CreateValidator();
        var token = CreateToken();

        var identity = await validator.ValidateAsync(token, CancellationToken.None);

        identity.TenantId.Should().Be(TenantId);
        identity.ObjectId.Should().Be("object-1");
        identity.Email.Should().Be("user@example.com");
        identity.DisplayName.Should().Be("Test User");
    }

    [Fact]
    public async Task ValidateAsync_WrongAudience_ThrowsForbidden()
    {
        var validator = CreateValidator();
        var token = CreateToken(audience: "someone-elses-app");

        var act = () => validator.ValidateAsync(token, CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task ValidateAsync_WrongTenant_ThrowsForbidden()
    {
        var validator = CreateValidator();
        var token = CreateToken(tid: "some-other-tenant");

        var act = () => validator.ValidateAsync(token, CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task ValidateAsync_MissingScope_ThrowsForbidden()
    {
        var validator = CreateValidator();
        var token = CreateToken(scp: "some_other_scope");

        var act = () => validator.ValidateAsync(token, CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task ValidateAsync_ExpiredToken_ThrowsForbidden()
    {
        var validator = CreateValidator();
        var token = CreateToken(expires: DateTime.UtcNow.AddMinutes(-5));

        var act = () => validator.ValidateAsync(token, CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task ValidateAsync_WrongSigningKey_ThrowsForbidden()
    {
        var validator = CreateValidator();
        var token = CreateToken(signingKey: OtherKey);

        var act = () => validator.ValidateAsync(token, CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task ValidateAsync_MissingEmailClaim_ThrowsForbidden()
    {
        var validator = CreateValidator();
        var token = CreateToken(email: null);

        var act = () => validator.ValidateAsync(token, CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    /// <summary>Constant stand-in for the DI-provided ConfigurationManager — no network calls in tests.</summary>
    private sealed class StaticConfigurationManager : IConfigurationManager<OpenIdConnectConfiguration>
    {
        private readonly OpenIdConnectConfiguration _configuration;
        public StaticConfigurationManager(OpenIdConnectConfiguration configuration) => _configuration = configuration;
        public Task<OpenIdConnectConfiguration> GetConfigurationAsync(CancellationToken cancel) => Task.FromResult(_configuration);
        public void RequestRefresh() { }
    }
}
