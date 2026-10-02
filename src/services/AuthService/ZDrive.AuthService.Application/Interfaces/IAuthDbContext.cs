using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Interfaces;

public interface IAuthDbContext
{
    DbSet<User> Users { get; }
    DbSet<Tenant> Tenants { get; }
    DbSet<RefreshToken> RefreshTokens { get; }
    DbSet<ExternalIdentity> ExternalIdentities { get; }
    DbSet<RecoveryCode> RecoveryCodes { get; }
    DbSet<TwoFactorChallenge> TwoFactorChallenges { get; }
    DbSet<TwoFactorGuard> TwoFactorGuards { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
