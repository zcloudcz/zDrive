using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Infrastructure.Persistence;
using ZDrive.Shared.Auth;

namespace ZDrive.PhotoService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isDevelopment)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<PhotoDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("PhotoDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "photos")));

        services.AddScoped<IPhotoDbContext>(sp => sp.GetRequiredService<PhotoDbContext>());

        // Authentication (validates JWTs issued by AuthService)
        var publicKeyPem = configuration["Jwt:RsaPublicKeyPem"];
        if (string.IsNullOrWhiteSpace(publicKeyPem))
        {
            if (!isDevelopment)
            {
                throw new InvalidOperationException(
                    "Jwt:RsaPublicKeyPem must be configured outside Development.");
            }

            // Same per-machine dev key pair AuthService signs with.
            publicKeyPem = DevJwtKeyProvider.GetOrCreateKeyPair().PublicKeyPem;
        }

        var rsa = RSA.Create();
        rsa.ImportFromPem(publicKeyPem);

        services.AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
            options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
        })
        .AddJwtBearer(options =>
        {
            // Keep raw JWT claim names ("sub", "tenant_id") — ClaimsHelper reads them directly.
            options.MapInboundClaims = false;

            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = configuration["Jwt:Issuer"] ?? "zdrive",
                ValidateAudience = true,
                ValidAudience = configuration["Jwt:Audience"] ?? "zdrive-api",
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new RsaSecurityKey(rsa),
                ClockSkew = TimeSpan.FromSeconds(30)
            };
        });

        services.AddAuthorization();

        return services;
    }
}
