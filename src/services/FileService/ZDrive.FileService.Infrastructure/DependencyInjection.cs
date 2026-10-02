using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Infrastructure.Http;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.FileService.Infrastructure.Persistence.Interceptors;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isDevelopment)
    {
        // Change feed: origin resolver (X-Device-Id), consumed by
        // FileChangeInterceptor below to tag rows with their writing device.
        services.AddSingleton<IChangeOrigin, HttpContextChangeOrigin>();
        services.AddSingleton<FileChangeInterceptor>();

        // EF Core + PostgreSQL
        // Snake-case naming matches the raw SQL (search query, index filters) used below.
        // The (sp, options) overload lets AddInterceptors pull the interceptor from DI
        // instead of constructing it by hand, so it shares the same registrations above.
        services.AddDbContext<FileDbContext>((sp, options) =>
            options.UseNpgsql(
                    configuration.GetConnectionString("ZDriveDb"),
                    npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "files"))
                .UseSnakeCaseNamingConvention()
                .AddInterceptors(sp.GetRequiredService<FileChangeInterceptor>()));

        services.AddScoped<IFileDbContext>(sp => sp.GetRequiredService<FileDbContext>());

        // Version retention policy (defaults apply when the section is missing)
        services.Configure<ZDrive.FileService.Application.Options.VersioningOptions>(
            configuration.GetSection(ZDrive.FileService.Application.Options.VersioningOptions.SectionName));

        // Per-user storage quota fallback (defaults apply when the section is missing)
        services.Configure<ZDrive.FileService.Application.Options.StorageOptions>(
            configuration.GetSection(ZDrive.FileService.Application.Options.StorageOptions.SectionName));

        // Public share download grants (defaults to an empty key — see
        // ShareDownloadGrantOptions.TryGetKey for the fail-closed behavior).
        // In Development only, an empty key falls back to the same per-machine
        // dev key StorageService reads (DevShareGrantKeyProvider) instead of a
        // literal in appsettings.Development.json — see PostConfigure below;
        // Configure<T> runs before it, so this section's own explicit value
        // (if ever set) still wins.
        services.Configure<ShareDownloadGrantOptions>(
            configuration.GetSection(ShareDownloadGrantOptions.SectionName));
        if (isDevelopment)
        {
            services.PostConfigure<ShareDownloadGrantOptions>(options =>
            {
                if (string.IsNullOrWhiteSpace(options.DownloadGrantKey))
                {
                    options.DownloadGrantKey = DevShareGrantKeyProvider.GetOrCreateKey();
                }
            });
        }

        // Authentication (JWT bearer scheme) is registered once by
        // ZDrive.AuthService.Infrastructure — see merge plan section 2a.
        services.AddAuthorization();

        return services;
    }
}
