using System.Security.Claims;
using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ClaimsHelperTests
{
    private static ClaimsPrincipal PrincipalWithQuotaClaim(string value) =>
        new(new ClaimsIdentity([new Claim(JwtConstants.QuotaBytesClaim, value)]));

    [Fact]
    public void GetQuotaBytes_NoClaim_ReturnsNull()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity());

        principal.GetQuotaBytes().Should().BeNull();
    }

    [Fact]
    public void GetQuotaBytes_GarbageValue_ReturnsNullInsteadOfThrowing()
    {
        var principal = PrincipalWithQuotaClaim("not-a-number");

        principal.GetQuotaBytes().Should().BeNull();
    }

    [Fact]
    public void GetQuotaBytes_Zero_ReturnsZero()
    {
        var principal = PrincipalWithQuotaClaim("0");

        principal.GetQuotaBytes().Should().Be(0);
    }

    [Fact]
    public void GetQuotaBytes_Negative_ReturnsNegative()
    {
        // Not "unlimited" — EnsureCanStoreAsync refuses any write once the
        // limit is <= usage, and usage is never negative, so zero/negative
        // already mean "everything refused".
        var principal = PrincipalWithQuotaClaim("-1");

        principal.GetQuotaBytes().Should().Be(-1);
    }
}
