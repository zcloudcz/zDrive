using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Interfaces;

public interface IAuthDbContext
{
    DbSet<User> Users { get; }
    DbSet<Tenant> Tenants { get; }
    DbSet<RefreshToken> RefreshTokens { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
