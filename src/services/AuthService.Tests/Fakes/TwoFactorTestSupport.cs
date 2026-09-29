using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using OtpNet;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;
using ZDrive.AuthService.Infrastructure.Auth;
using ZDrive.AuthService.Infrastructure.Persistence;

namespace ZDrive.AuthService.Tests.Fakes;

/// <summary>
/// Shared setup for 2FA handler tests: real TOTP + real Data Protection (with
/// a throwaway key ring), EF InMemory storage. Secrets are generated at run
/// time so no TOTP seed lives in the source.
/// </summary>
public sealed class TwoFactorTestSupport
{
    public AuthDbContext Db { get; } = new(
        new DbContextOptionsBuilder<AuthDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    public ITotpService Totp { get; } = new TotpService();
    public ISecretProtector Protector { get; } = new DataProtectionSecretProtector(new EphemeralDataProtectionProvider());
    public IPasswordHasher Hasher { get; } = new Argon2PasswordHasher();
    public TwoFactorVerifier Verifier { get; }

    public TwoFactorTestSupport() => Verifier = new TwoFactorVerifier(Db, Totp, Protector);

    public async Task<User> AddUserAsync(string? password = "Password1")
    {
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "T" };
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = $"{Guid.NewGuid():N}@example.com",
            PasswordHash = password is null ? null : Hasher.Hash(password),
            DisplayName = "User",
            TenantId = tenant.Id
        };
        Db.Tenants.Add(tenant);
        Db.Users.Add(user);
        await Db.SaveChangesAsync();
        return user;
    }

    /// <summary>Puts <paramref name="user"/> into the 2FA-enabled state; returns the plain secret.</summary>
    public async Task<string> EnableTwoFactorAsync(User user)
    {
        var secret = Totp.GenerateSecret();
        user.TwoFactorSecretProtected = Protector.Protect(secret);
        user.TwoFactorEnabledAt = DateTime.UtcNow;
        await Db.SaveChangesAsync();
        return secret;
    }

    public static string CodeFor(string secret, DateTime? at = null) =>
        new Totp(Base32Encoding.ToBytes(secret)).ComputeTotp(at ?? DateTime.UtcNow);
}
