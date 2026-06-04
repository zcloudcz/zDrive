using System.IdentityModel.Tokens.Jwt;
using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Xunit;
using ZDrive.AuthService.Domain.Entities;
using ZDrive.AuthService.Domain.Enums;
using ZDrive.AuthService.Infrastructure.Auth;
using SharedJwt = ZDrive.Shared.Auth.JwtConstants;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class JwtTokenGeneratorTests
{
    private static readonly RSA Rsa = RSA.Create(2048);

    private static JwtTokenGenerator CreateGenerator()
    {
        var privateKeyPem = Rsa.ExportRSAPrivateKeyPem();
        var publicKeyPem = Rsa.ExportSubjectPublicKeyInfoPem();

        var settings = Options.Create(new JwtSettings
        {
            RsaPrivateKeyPem = privateKeyPem,
            RsaPublicKeyPem = publicKeyPem,
            Issuer = "zdrive-test",
            Audience = "zdrive-api-test",
            AccessTokenExpirationMinutes = 15,
            RefreshTokenExpirationDays = 30
        });

        return new JwtTokenGenerator(settings);
    }

    private static User CreateTestUser() => new()
    {
        Id = Guid.NewGuid(),
        Email = "test@example.com",
        DisplayName = "Test User",
        PasswordHash = "irrelevant",
        Role = Role.Owner,
        TenantId = Guid.NewGuid()
    };

    [Fact]
    public void GenerateAccessToken_ReturnsValidJwt()
    {
        var generator = CreateGenerator();
        var user = CreateTestUser();

        var token = generator.GenerateAccessToken(user);

        token.Should().NotBeNullOrWhiteSpace();

        var handler = new JwtSecurityTokenHandler();
        var jwt = handler.ReadJwtToken(token);

        jwt.Issuer.Should().Be("zdrive-test");
        jwt.Audiences.Should().Contain("zdrive-api-test");
        jwt.Claims.Should().Contain(c => c.Type == SharedJwt.UserIdClaim && c.Value == user.Id.ToString());
        jwt.Claims.Should().Contain(c => c.Type == SharedJwt.TenantIdClaim && c.Value == user.TenantId.ToString());
        jwt.Claims.Should().Contain(c => c.Type == SharedJwt.RoleClaim && c.Value == "Owner");
    }

    [Fact]
    public void GenerateAccessToken_CanBeValidatedWithPublicKey()
    {
        var generator = CreateGenerator();
        var user = CreateTestUser();
        var token = generator.GenerateAccessToken(user);

        var handler = new JwtSecurityTokenHandler();
        var validationParams = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = "zdrive-test",
            ValidateAudience = true,
            ValidAudience = "zdrive-api-test",
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new RsaSecurityKey(Rsa),
            ClockSkew = TimeSpan.FromSeconds(30)
        };

        var principal = handler.ValidateToken(token, validationParams, out var validatedToken);
        principal.Should().NotBeNull();
        validatedToken.Should().NotBeNull();
    }

    [Fact]
    public void GenerateRefreshToken_ReturnsNonEmptyBase64()
    {
        var generator = CreateGenerator();

        var token = generator.GenerateRefreshToken();

        token.Should().NotBeNullOrWhiteSpace();
        // Should be valid base64
        var bytes = Convert.FromBase64String(token);
        bytes.Length.Should().Be(64);
    }

    [Fact]
    public void GenerateRefreshToken_ProducesUniqueTokens()
    {
        var generator = CreateGenerator();

        var token1 = generator.GenerateRefreshToken();
        var token2 = generator.GenerateRefreshToken();

        token1.Should().NotBe(token2);
    }
}
