using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.SyncService.Infrastructure.Persistence;

namespace ZDrive.SyncService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isDevelopment)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<SyncDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("ZDriveDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "sync")));

        services.AddScoped<ISyncDbContext>(sp => sp.GetRequiredService<SyncDbContext>());

        // Authentication (JWT bearer scheme) is registered once by
        // ZDrive.AuthService.Infrastructure — see merge plan section 2a.
        services.AddAuthorization();

        return services;
    }
}
