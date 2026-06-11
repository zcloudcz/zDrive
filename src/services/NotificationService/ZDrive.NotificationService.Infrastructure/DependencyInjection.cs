using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using ZDrive.NotificationService.Application.Interfaces;
using ZDrive.NotificationService.Domain.Entities;
using ZDrive.NotificationService.Infrastructure.Persistence;
using ZDrive.NotificationService.Infrastructure.SignalR;
using ZDrive.Shared.Auth;

namespace ZDrive.NotificationService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isDevelopment)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<NotificationDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("NotificationDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "notifications")));

        services.AddScoped<INotificationDbContext>(sp => sp.GetRequiredService<NotificationDbContext>());

        // Connection mapping (singleton — shared across all hubs)
        services.AddSingleton<ConnectionMapping>();

        // SignalR notification pusher
        services.AddScoped<INotificationPusher, SignalRNotificationPusher>();

        // Authentication
        var jwtSection = configuration.GetSection("Jwt");
        var publicKeyPem = jwtSection["RsaPublicKeyPem"];
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
                ValidIssuer = jwtSection["Issuer"] ?? "zdrive",
                ValidateAudience = true,
                ValidAudience = jwtSection["Audience"] ?? "zdrive-api",
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new RsaSecurityKey(rsa),
                ClockSkew = TimeSpan.FromSeconds(30)
            };

            // Allow SignalR to read JWT from query string for WebSocket connections
            options.Events = new JwtBearerEvents
            {
                OnMessageReceived = context =>
                {
                    var accessToken = context.Request.Query["access_token"];
                    var path = context.HttpContext.Request.Path;
                    if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs/sync"))
                    {
                        context.Token = accessToken;
                    }
                    return Task.CompletedTask;
                }
            };
        });

        services.AddAuthorization();

        return services;
    }
}
