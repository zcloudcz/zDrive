using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Infrastructure.Auth;
using ZDrive.AuthService.Infrastructure.Persistence;

namespace ZDrive.AuthService.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // EF Core + PostgreSQL
        services.AddDbContext<AuthDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("AuthDb"),
                npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "auth")));

        services.AddScoped<IAuthDbContext>(sp => sp.GetRequiredService<AuthDbContext>());

        // JWT
        services.Configure<JwtSettings>(configuration.GetSection(JwtSettings.SectionName));
        services.AddSingleton<IJwtTokenGenerator, JwtTokenGenerator>();

        // Password hashing
        services.AddSingleton<IPasswordHasher, Argon2PasswordHasher>();

        // Authentication
        var jwtSection = configuration.GetSection(JwtSettings.SectionName);
        var publicKeyPem = jwtSection["RsaPublicKeyPem"]!;
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

        services.AddAuthorization();

        return services;
    }
}
