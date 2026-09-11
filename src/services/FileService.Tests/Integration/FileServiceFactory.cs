using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Tests.Integration;

public sealed class FileServiceFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    // Created eagerly so it exists before the host is built; tests sign JWTs
    // with this key and the service is configured to validate against it.
    private readonly RSA _rsa = RSA.Create(2048);

    public const int MaxVersionsPerFile = 3;

    public Guid TestUserId { get; } = Guid.NewGuid();
    public Guid TestTenantId { get; } = Guid.NewGuid();

    // Shared by FileChangeInterceptor (stamps FileChange.OccurredAt) and
    // GetFileChangesQueryHandler (computes the hold-back cutoff) — both
    // resolve TimeProvider from DI, so this single instance drives both.
    public ManualTimeProvider TimeProvider { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        // Make the service validate tokens signed by this factory's key instead
        // of the per-machine dev key pair. PostConfigure runs after the app's own
        // service registration, so it reliably overrides the signing key.
        builder.ConfigureTestServices(services =>
        {
            services.PostConfigure<JwtBearerOptions>(
                JwtBearerDefaults.AuthenticationScheme,
                options => options.TokenValidationParameters.IssuerSigningKey = new RsaSecurityKey(_rsa));

            // Small retention limit so version pruning is testable without
            // creating dozens of versions (see VersionFlowTests).
            services.PostConfigure<ZDrive.FileService.Application.Options.VersioningOptions>(
                options => options.MaxVersionsPerFile = MaxVersionsPerFile);
        });

        builder.ConfigureServices(services =>
        {
            // Remove the real DbContext registration
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<FileDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            // Register DbContext pointing to testcontainer
            // Same options as the real registration — snake_case matters because
            // the search query and index filters use raw snake_case SQL.
            // MigrationsHistoryTable must be schema-qualified here too (matching
            // DependencyInjection.cs) — otherwise it falls back to the connection's
            // search_path, which points at a schema that doesn't exist until the
            // first migration creates it, and Migrate() fails before it gets there.
            services.AddDbContext<FileDbContext>((sp, options) =>
                options.UseNpgsql(_postgres.GetConnectionString() + ";Search Path=files",
                        npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "files"))
                    .UseSnakeCaseNamingConvention()
                    .AddInterceptors(sp.GetRequiredService<ZDrive.FileService.Infrastructure.Persistence.Interceptors.FileChangeInterceptor>()));

            // Replace the real clock with a manually-advanceable one so tests
            // can exercise the change feed's 5-second hold-back deterministically.
            var timeProviderDescriptor = services.SingleOrDefault(d => d.ServiceType == typeof(TimeProvider));
            if (timeProviderDescriptor is not null)
                services.Remove(timeProviderDescriptor);
            services.AddSingleton<TimeProvider>(TimeProvider);
        });
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        // Apply migrations / create schema
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FileDbContext>();
        await db.Database.MigrateAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        _rsa.Dispose();
        await _postgres.DisposeAsync();
    }

    /// <summary>
    /// Creates an HttpClient with a valid JWT for the test user.
    /// </summary>
    public HttpClient CreateAuthenticatedClient()
    {
        var client = CreateClient();
        var token = GenerateTestToken(TestUserId, TestTenantId);
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    /// <summary>
    /// Creates an HttpClient with a valid JWT for a specific user.
    /// </summary>
    public HttpClient CreateAuthenticatedClient(Guid userId, Guid tenantId)
    {
        var client = CreateClient();
        var token = GenerateTestToken(userId, tenantId);
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private string GenerateTestToken(Guid userId, Guid tenantId)
    {
        var signingCredentials = new SigningCredentials(
            new RsaSecurityKey(_rsa),
            SecurityAlgorithms.RsaSha256);

        var claims = new[]
        {
            new Claim(ZDrive.Shared.Auth.JwtConstants.UserIdClaim, userId.ToString()),
            new Claim(ZDrive.Shared.Auth.JwtConstants.TenantIdClaim, tenantId.ToString()),
            new Claim(ZDrive.Shared.Auth.JwtConstants.RoleClaim, "Owner"),
            new Claim(ZDrive.Shared.Auth.JwtConstants.DisplayNameClaim, "Test User"),
            new Claim(JwtRegisteredClaimNames.Email, "test@zdrive.test"),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var token = new JwtSecurityToken(
            issuer: "zdrive",
            audience: "zdrive-api",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(15),
            signingCredentials: signingCredentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
