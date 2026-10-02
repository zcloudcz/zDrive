using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.DataProtection.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using ZDrive.AuthService.Application.Auth;
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

        // TOTP 2FA. Secrets are encrypted with Data Protection, so the key ring
        // must survive restarts/redeploys on every host: if it is lost, every
        // stored secret becomes undecryptable and 2FA users are locked out.
        // Keys therefore live in the auth database (auth."DataProtectionKeys").
        services.AddDataProtection()
            .SetApplicationName("zdrive")
            .PersistKeysToDbContext<AuthDbContext>();
        services.AddSingleton<ISecretProtector, DataProtectionSecretProtector>();
        services.AddSingleton<ITotpService, TotpService>();
        services.Configure<TwoFactorOptions>(configuration.GetSection(TwoFactorOptions.SectionName));

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

        // Entra External ID federation exchange — opt-in per deployment. Fail
        // fast at startup (same spirit as the Jwt key check above) rather than
        // let a half-configured section surface as a confusing 401 at runtime.
        var entraSection = configuration.GetSection(EntraOptions.SectionName);
        services.Configure<EntraOptions>(entraSection);
        var entraOptions = entraSection.Get<EntraOptions>() ?? new EntraOptions();
        if (entraOptions.Enabled &&
            (string.IsNullOrWhiteSpace(entraOptions.TenantId) ||
             string.IsNullOrWhiteSpace(entraOptions.Audience) ||
             string.IsNullOrWhiteSpace(entraOptions.RequiredScope)))
        {
            throw new InvalidOperationException(
                "Entra:TenantId, Entra:Audience and Entra:RequiredScope must be configured when Entra:Enabled is true.");
        }

        services.AddSingleton<IConfigurationManager<OpenIdConnectConfiguration>>(_ =>
            new ConfigurationManager<OpenIdConnectConfiguration>(
                $"https://{entraOptions.TenantId}.ciamlogin.com/{entraOptions.TenantId}/v2.0/.well-known/openid-configuration",
                new OpenIdConnectConfigurationRetriever()));
        services.AddSingleton<IEntraTokenValidator, EntraTokenValidator>();

        return services;
    }
}
