using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZDrive.AuthService.Application.Commands.EntraExchange;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.AuthService.Tests.Fakes;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class EntraExchangeCommandHandlerTests
{
    private static AuthDbContext CreateDb() => new(
        new DbContextOptionsBuilder<AuthDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    private static EntraIdentity CreateIdentity(
        string tenantId = "tenant-1", string objectId = "object-1", string email = "user@example.com") =>
        new(tenantId, objectId, email, "Test User");

    [Fact]
    public async Task Handle_FirstExchange_CreatesUserTenantAndMappingWithNullPasswordHash()
    {
        await using var db = CreateDb();
        var handler = new EntraExchangeCommandHandler(
            db, FakeEntraTokenValidator.Returning(CreateIdentity()), new FakeJwtTokenGenerator());

        await handler.Handle(new EntraExchangeCommand("token"), CancellationToken.None);

        var user = await db.Users.SingleAsync();
        user.PasswordHash.Should().BeNull();
        user.Email.Should().Be("user@example.com");

        var mapping = await db.ExternalIdentities.SingleAsync();
        mapping.UserId.Should().Be(user.Id);
        mapping.ProviderTenantId.Should().Be("tenant-1");
        mapping.ObjectId.Should().Be("object-1");

        (await db.Tenants.CountAsync()).Should().Be(1);
    }

    [Fact]
    public async Task Handle_SecondExchangeSameIdentity_ReturnsSameUserAndCreatesNothingNew()
    {
        await using var db = CreateDb();
        var validator = FakeEntraTokenValidator.Returning(CreateIdentity());
        var handler = new EntraExchangeCommandHandler(db, validator, new FakeJwtTokenGenerator());

        await handler.Handle(new EntraExchangeCommand("token"), CancellationToken.None);
        var firstUserId = (await db.Users.SingleAsync()).Id;

        await handler.Handle(new EntraExchangeCommand("token"), CancellationToken.None);

        (await db.Users.CountAsync()).Should().Be(1);
        (await db.ExternalIdentities.CountAsync()).Should().Be(1);
        (await db.Users.SingleAsync()).Id.Should().Be(firstUserId);
    }

    [Fact]
    public async Task Handle_EmailAlreadyUsedByPasswordAccount_ThrowsConflict()
    {
        await using var db = CreateDb();
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "Existing" };
        db.Tenants.Add(tenant);
        db.Users.Add(new User
        {
            Id = Guid.NewGuid(),
            Email = "user@example.com",
            PasswordHash = "some-hash",
            DisplayName = "Existing User",
            TenantId = tenant.Id
        });
        await db.SaveChangesAsync();

        var handler = new EntraExchangeCommandHandler(
            db, FakeEntraTokenValidator.Returning(CreateIdentity()), new FakeJwtTokenGenerator());

        var act = () => handler.Handle(new EntraExchangeCommand("token"), CancellationToken.None);

        await act.Should().ThrowAsync<ConflictException>();
    }

    // Reproduces the race window without threads: the winner's user + mapping
    // are seeded (via a second context on the same InMemory store, so the
    // write is visible immediately — there's no way to hold it back to land
    // strictly between the loser's own lookup and its email check with the
    // fakes this test suite has). That means this test cannot exercise the
    // race through the public Handle() entry point — Handle's own mapping
    // lookup would already hit and never reach CreateUserAsync. Instead it
    // invokes the private CreateUserAsync directly via reflection, which is
    // exactly the method the fix lives in: given an email already "taken"
    // and a mapping that already exists for the same (tid, oid), it must
    // return the mapped user instead of throwing ConflictException.
    [Fact]
    public async Task CreateUserAsync_EmailTakenButMappingExistsForSameIdentity_ReturnsMappedUserInsteadOfConflict()
    {
        await using var db = CreateDb();
        var identity = CreateIdentity();

        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "Winner's Space" };
        var winner = new User
        {
            Id = Guid.NewGuid(),
            Email = identity.Email,
            PasswordHash = null,
            DisplayName = "Winner",
            TenantId = tenant.Id
        };
        var mapping = new ExternalIdentity
        {
            Id = Guid.NewGuid(),
            UserId = winner.Id,
            ProviderTenantId = identity.TenantId,
            ObjectId = identity.ObjectId
        };
        db.Tenants.Add(tenant);
        db.Users.Add(winner);
        db.ExternalIdentities.Add(mapping);
        await db.SaveChangesAsync();

        var handler = new EntraExchangeCommandHandler(
            db, FakeEntraTokenValidator.Returning(identity), new FakeJwtTokenGenerator());

        var createUserAsync = typeof(EntraExchangeCommandHandler).GetMethod(
            "CreateUserAsync", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!;
        var task = (Task<User>)createUserAsync.Invoke(handler, [identity, CancellationToken.None])!;
        var result = await task;

        result.Id.Should().Be(winner.Id);
        (await db.Users.CountAsync()).Should().Be(1);
    }

    [Fact]
    public async Task Handle_ValidatorFailure_PropagatesForbidden()
    {
        await using var db = CreateDb();
        var handler = new EntraExchangeCommandHandler(
            db, FakeEntraTokenValidator.Throwing(new ForbiddenException("invalid token")), new FakeJwtTokenGenerator());

        var act = () => handler.Handle(new EntraExchangeCommand("bad-token"), CancellationToken.None);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task Handle_IssuesRefreshToken_WithAbsoluteExpiresAtAroundTwentyFourHours()
    {
        await using var db = CreateDb();
        var handler = new EntraExchangeCommandHandler(
            db, FakeEntraTokenValidator.Returning(CreateIdentity()), new FakeJwtTokenGenerator());

        var before = DateTime.UtcNow;
        var result = await handler.Handle(new EntraExchangeCommand("token"), CancellationToken.None);
        var after = DateTime.UtcNow;

        var refreshToken = await db.RefreshTokens.SingleAsync(rt => rt.Token == result.RefreshToken);
        refreshToken.AbsoluteExpiresAt.Should().NotBeNull();
        refreshToken.AbsoluteExpiresAt!.Value.Should()
            .BeOnOrAfter(before.AddHours(24)).And.BeOnOrBefore(after.AddHours(24));
    }
}
