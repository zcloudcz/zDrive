using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZDrive.AuthService.Application.Commands.Login;
using ZDrive.AuthService.Domain.Entities;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.AuthService.Tests.Fakes;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class LoginCommandHandlerTests
{
    private static AuthDbContext CreateDb() => new(
        new DbContextOptionsBuilder<AuthDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    [Fact]
    public async Task Handle_UserWithNullPasswordHash_FailsLikeWrongPassword()
    {
        await using var db = CreateDb();
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "T" };
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = "entra-only@example.com",
            PasswordHash = null, // Entra-only account
            DisplayName = "Entra User",
            TenantId = tenant.Id
        };
        db.Tenants.Add(tenant);
        db.Users.Add(user);
        await db.SaveChangesAsync();

        // Hasher always says "match" — proves the null-hash guard itself is
        // what rejects the login, not a coincidence of the hasher's behavior.
        var handler = new LoginCommandHandler(db, new FakeAlwaysVerifiesPasswordHasher(), new FakeJwtTokenGenerator());

        var act = () => handler.Handle(new LoginCommand("entra-only@example.com", "any-password"), CancellationToken.None);

        var exception = await act.Should().ThrowAsync<NotFoundException>();
        // Same message a wrong password produces — the response must not
        // reveal that the account is federated.
        exception.Which.Message.Should().Be(new NotFoundException("User", "entra-only@example.com").Message);
    }
}
