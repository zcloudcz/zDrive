using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Tests.Fakes;

/// <summary>
/// Deterministic stand-in for IJwtTokenGenerator — handler tests care about
/// what a handler does with the token strings it gets back, not about real
/// JWT signing (that's covered by JwtTokenGeneratorTests).
/// </summary>
public sealed class FakeJwtTokenGenerator : IJwtTokenGenerator
{
    private int _refreshTokenCounter;

    public string GenerateAccessToken(User user) => $"access-token-for-{user.Id}";

    public string GenerateRefreshToken() => $"refresh-token-{++_refreshTokenCounter}";
}
