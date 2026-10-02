using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Infrastructure.Persistence;

namespace ZDrive.PhotoService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<PhotoDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("PhotoDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "photos")));

        services.AddScoped<IPhotoDbContext>(sp => sp.GetRequiredService<PhotoDbContext>());

        // Authentication (JWT bearer scheme) is registered once by
        // ZDrive.AuthService.Infrastructure — see merge plan section 2a.
        services.AddAuthorization();

        return services;
    }
}
