using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;
using SharedJwt = ZDrive.Shared.Auth.JwtConstants;

namespace ZDrive.AuthService.Infrastructure.Auth;

public sealed class JwtTokenGenerator : IJwtTokenGenerator
{
    private readonly JwtSettings _settings;
    private readonly RSA _rsa;

    public JwtTokenGenerator(IOptions<JwtSettings> settings)
    {
        _settings = settings.Value;
        _rsa = RSA.Create();
        _rsa.ImportFromPem(_settings.RsaPrivateKeyPem);
    }

    public string GenerateAccessToken(User user)
    {
        var signingCredentials = new SigningCredentials(
            new RsaSecurityKey(_rsa),
            SecurityAlgorithms.RsaSha256);

        var claims = new[]
        {
            new Claim(SharedJwt.UserIdClaim, user.Id.ToString()),
            new Claim(SharedJwt.TenantIdClaim, user.TenantId.ToString()),
            new Claim(SharedJwt.RoleClaim, user.Role.ToString()),
            new Claim(SharedJwt.DisplayNameClaim, user.DisplayName),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var token = new JwtSecurityToken(
            issuer: _settings.Issuer,
            audience: _settings.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_settings.AccessTokenExpirationMinutes),
            signingCredentials: signingCredentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public string GenerateRefreshToken()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
    }
}
