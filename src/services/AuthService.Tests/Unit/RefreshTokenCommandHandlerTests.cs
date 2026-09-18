using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZDrive.AuthService.Application.Commands.RefreshToken;
using ZDrive.AuthService.Domain.Entities;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.AuthService.Tests.Fakes;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class RefreshTokenCommandHandlerTests
{
    private static AuthDbContext CreateDb() => new(
        new DbContextOptionsBuilder<AuthDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    private static async Task<User> SeedUserAsync(AuthDbContext db)
    {
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "T" };
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = "user@example.com",
            PasswordHash = "hash",
            DisplayName = "User",
            TenantId = tenant.Id,
            Tenant = tenant
        };
        db.Tenants.Add(tenant);
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user;
    }

    [Fact]
    public async Task Handle_AbsoluteExpiresAtInThePast_ThrowsNotFound()
    {
        await using var db = CreateDb();
        var user = await SeedUserAsync(db);
        db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = "capped-token",
            UserId = user.Id,
            ExpiresAt = DateTime.UtcNow.AddDays(30), // ExpiresAt itself not reached yet...
            AbsoluteExpiresAt = DateTime.UtcNow.AddMinutes(-1) // ...but the absolute cap already has
        });
        await db.SaveChangesAsync();

        var handler = new RefreshTokenCommandHandler(db, new FakeJwtTokenGenerator());

        var act = () => handler.Handle(new RefreshTokenCommand("capped-token"), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Handle_CappedToken_ReplacementInheritsCapAndExpiresAtNeverExceedsIt()
    {
        await using var db = CreateDb();
        var user = await SeedUserAsync(db);
        var cap = DateTime.UtcNow.AddHours(2); // well under the usual 30-day window
        db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = "capped-token",
            UserId = user.Id,
            ExpiresAt = cap,
            AbsoluteExpiresAt = cap
        });
        await db.SaveChangesAsync();

        var handler = new RefreshTokenCommandHandler(db, new FakeJwtTokenGenerator());

        var result = await handler.Handle(new RefreshTokenCommand("capped-token"), CancellationToken.None);

        var newToken = await db.RefreshTokens.SingleAsync(rt => rt.Token == result.RefreshToken);
        newToken.AbsoluteExpiresAt.Should().Be(cap);
        newToken.ExpiresAt.Should().Be(cap); // min(now+30d, cap) == cap here
    }

    [Fact]
    public async Task Handle_LegacyTokenWithNoCap_StillRotatesToThirtyDays()
    {
        await using var db = CreateDb();
        var user = await SeedUserAsync(db);
        db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = "legacy-token",
            UserId = user.Id,
            ExpiresAt = DateTime.UtcNow.AddDays(29),
            AbsoluteExpiresAt = null
        });
        await db.SaveChangesAsync();

        var handler = new RefreshTokenCommandHandler(db, new FakeJwtTokenGenerator());

        var before = DateTime.UtcNow;
        var result = await handler.Handle(new RefreshTokenCommand("legacy-token"), CancellationToken.None);
        var after = DateTime.UtcNow;

        var newToken = await db.RefreshTokens.SingleAsync(rt => rt.Token == result.RefreshToken);
        newToken.AbsoluteExpiresAt.Should().BeNull();
        newToken.ExpiresAt.Should().BeOnOrAfter(before.AddDays(30)).And.BeOnOrBefore(after.AddDays(30));
    }
}
