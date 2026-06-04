using System.Security.Cryptography;
using Azure.Storage;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;
using ZDrive.StorageService.Infrastructure.Persistence;

namespace ZDrive.StorageService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<StorageDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("StorageDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory")));

        services.AddScoped<IStorageDbContext>(sp => sp.GetRequiredService<StorageDbContext>());

        // Azure Blob Storage
        var blobConnectionString = configuration.GetConnectionString("AzureBlobStorage")
            ?? configuration["AZURE_STORAGE_CONNECTION_STRING"]
            ?? "UseDevelopmentStorage=true";

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

        // Authentication (JWT validation — same pattern as AuthService, for incoming tokens)
        var jwtSection = configuration.GetSection("Jwt");
        var publicKeyPem = jwtSection["RsaPublicKeyPem"];

        if (!string.IsNullOrEmpty(publicKeyPem))
        {
            var rsa = RSA.Create();
            rsa.ImportFromPem(publicKeyPem);

            services.AddAuthentication(options =>
            {
                options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
            })
            .AddJwtBearer(options =>
            {
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = jwtSection["Issuer"] ?? "zdrive",
                    ValidateAudience = true,
                    ValidAudience = jwtSection["Audience"] ?? "zdrive-api",
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new RsaSecurityKey(rsa),
                    ClockSkew = TimeSpan.FromSeconds(30)
                };
            });
        }

        services.AddAuthorization();

        return services;
    }
}
