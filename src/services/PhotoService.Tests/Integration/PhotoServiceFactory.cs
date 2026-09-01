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
using ZDrive.PhotoService.Infrastructure.Persistence;
using ZDrive.Shared.Auth;

namespace ZDrive.PhotoService.Tests.Integration;

public sealed class PhotoServiceFactory : WebApplicationFactory<Program>, IAsyncLifetime
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

    public Guid TestUserId { get; } = Guid.NewGuid();
    public Guid TestTenantId { get; } = Guid.NewGuid();

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
        });

        builder.ConfigureServices(services =>
        {
            // Remove the real DbContext registration
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<PhotoDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            // Register DbContext pointing to testcontainer
            services.AddDbContext<PhotoDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString()));
        });
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        // Create the schema. No EF migrations yet (see PhotoService Program.cs).
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        await db.Database.EnsureCreatedAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        _rsa.Dispose();
        try
        {
            // Stop the test host before tearing down the container it depends on,
            // otherwise the host is leaked and its DB calls fail mid-shutdown.
            await base.DisposeAsync();
        }
        finally
        {
            // Always dispose the container, even if host shutdown throws.
            await _postgres.DisposeAsync();
        }
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

    /// <summary>
    /// Runs an action against a freshly scoped DbContext, disposing the scope
    /// afterwards. Needed for Memories, which are only ever created by the
    /// (out-of-scope) AI pipeline — there is no API to create one, so tests
    /// seed directly, exactly like the daily cron job would.
    /// </summary>
    public async Task SeedAsync(Func<PhotoDbContext, Task> seed)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        await seed(db);
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
