using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Infrastructure.Auth;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.Shared.Auth;

namespace ZDrive.AuthService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isDevelopment)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<AuthDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("AuthDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "auth")));

        services.AddScoped<IAuthDbContext>(sp => sp.GetRequiredService<AuthDbContext>());

        // JWT — key material comes from configuration (env vars / Key Vault in
        // production). In Development we fall back to a per-machine generated
        // key pair so no private key ever lives in the repository.
        var jwtSection = configuration.GetSection(JwtSettings.SectionName);
        var privateKeyPem = jwtSection["RsaPrivateKeyPem"];
        var publicKeyPem = jwtSection["RsaPublicKeyPem"];

        if (string.IsNullOrWhiteSpace(privateKeyPem) || string.IsNullOrWhiteSpace(publicKeyPem))
        {
            if (!isDevelopment)
            {
                throw new InvalidOperationException(
                    "Jwt:RsaPrivateKeyPem and Jwt:RsaPublicKeyPem must be configured outside Development.");
            }

            (privateKeyPem, publicKeyPem) = DevJwtKeyProvider.GetOrCreateKeyPair();
        }

        services.Configure<JwtSettings>(jwtSection);
        services.PostConfigure<JwtSettings>(settings =>
        {
            settings.RsaPrivateKeyPem = privateKeyPem;
            settings.RsaPublicKeyPem = publicKeyPem;
        });
        services.AddSingleton<IJwtTokenGenerator, JwtTokenGenerator>();

        // Password hashing
        services.AddSingleton<IPasswordHasher, Argon2PasswordHasher>();

        // Authentication
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
        });

        services.AddAuthorization();

        return services;
    }
}
