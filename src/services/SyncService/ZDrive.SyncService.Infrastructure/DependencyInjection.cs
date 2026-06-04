using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.SyncService.Infrastructure.Persistence;

namespace ZDrive.SyncService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<SyncDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("SyncDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "sync")));

        services.AddScoped<ISyncDbContext>(sp => sp.GetRequiredService<SyncDbContext>());

        // Authentication (validates JWTs issued by AuthService)
        var publicKeyPem = configuration["Jwt:RsaPublicKeyPem"]!;
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
