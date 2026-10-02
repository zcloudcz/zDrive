using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.PhotoService.Application.Options;
using ZDrive.PhotoService.Infrastructure.Ingest;
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
                configuration.GetConnectionString("ZDriveDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "photos")));

        services.AddScoped<IPhotoDbContext>(sp => sp.GetRequiredService<PhotoDbContext>());

        services.Configure<PhotoIngestOptions>(configuration.GetSection(PhotoIngestOptions.SectionName));
        services.Configure<PhotoThumbnailOptions>(configuration.GetSection(PhotoThumbnailOptions.SectionName));
        services.AddSingleton<IPhotoImageProcessor>(sp =>
            new SkiaPhotoImageProcessor(sp.GetRequiredService<Microsoft.Extensions.Options.IOptions<PhotoIngestOptions>>().Value.MaxDecodedPixels));
        services.AddSingleton<PhotoIngestPump>();

        // Authentication (JWT bearer scheme) is registered once by
        // ZDrive.AuthService.Infrastructure — see merge plan section 2a.
        services.AddAuthorization();

        return services;
    }
}
