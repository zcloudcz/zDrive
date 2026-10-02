using Azure.Storage;
using Azure.Storage.Blobs;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;
using ZDrive.StorageService.Infrastructure.Persistence;
using ZDrive.Shared.Auth;

namespace ZDrive.StorageService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isDevelopment)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<StorageDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("ZDriveDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "storage")));

        services.AddScoped<IStorageDbContext>(sp => sp.GetRequiredService<StorageDbContext>());

        // Public share download grants (defaults to an empty key — see
        // ShareDownloadGrantOptions.TryGetKey for the fail-closed behavior).
        // In Development only, an empty key falls back to the same per-machine
        // dev key FileService signs with (DevShareGrantKeyProvider) instead of
        // a literal in appsettings.Development.json.
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

        // Azure Blob Storage — same fail-fast policy as the JWT key below: the
        // Azurite fallback only applies in Development, never silently in prod.
        var blobConnectionString = configuration.GetConnectionString("AzureBlobStorage")
            ?? configuration["AZURE_STORAGE_CONNECTION_STRING"];

        if (string.IsNullOrWhiteSpace(blobConnectionString))
        {
            if (!isDevelopment)
            {
                throw new InvalidOperationException(
                    "ConnectionStrings:AzureBlobStorage (or AZURE_STORAGE_CONNECTION_STRING) must be configured outside Development.");
            }

            blobConnectionString = "UseDevelopmentStorage=true";
        }

        var blobServiceClient = new BlobServiceClient(blobConnectionString);
        services.AddSingleton(blobServiceClient);

        // Try to extract shared key credential for SAS generation
        StorageSharedKeyCredential? sharedKeyCredential = null;
        try
        {
            // Parse account name and key from connection string
            var parts = blobConnectionString.Split(';')
                .Select(p => p.Split(['='], 2))
                .Where(p => p.Length == 2)
                .ToDictionary(p => p[0].Trim(), p => p[1].Trim(), StringComparer.OrdinalIgnoreCase);

            if (parts.TryGetValue("AccountName", out var accountName) &&
                parts.TryGetValue("AccountKey", out var accountKey))
            {
                sharedKeyCredential = new StorageSharedKeyCredential(accountName, accountKey);
            }
            else if (blobConnectionString.Contains("UseDevelopmentStorage=true", StringComparison.OrdinalIgnoreCase))
            {
                // Azurite well-known credentials
                sharedKeyCredential = new StorageSharedKeyCredential(
                    "devstoreaccount1",
                    "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==");
            }
        }
        catch
        {
            // If parsing fails, SAS generation will return direct URLs
        }

        services.AddSingleton(sp => sharedKeyCredential!);
        services.AddSingleton<IBlobStorageService, AzureBlobStorageService>();

        // Authentication (JWT bearer scheme) is registered once by
        // ZDrive.AuthService.Infrastructure — see merge plan section 2a.
        services.AddAuthorization();

        return services;
    }
}
