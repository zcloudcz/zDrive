using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Testcontainers.PostgreSql;
using Xunit;
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

    // Generated at runtime (not a literal) so nothing here looks like a
    // committed secret to the repo's gitleaks scan. This suite never
    // validates a grant string against the key, only the DTO fields — the
    // key just needs to be present so ShareDownloadGrantOptions.TryGetKey
    // succeeds and the download-grant endpoint isn't fail-closed off.
    public static readonly string TestShareGrantKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

    public Guid TestUserId { get; } = Guid.NewGuid();
    public Guid TestTenantId { get; } = Guid.NewGuid();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        // Point all four connection strings at this factory's ephemeral
        // Testcontainers instance instead of the dev connection strings in
        // appsettings.json. AddInfrastructure reads this configuration value
        // lazily — inside the AddDbContext options delegate, evaluated on
        // first DbContext resolution, not when AddInfrastructure itself runs —
        // so overriding just the values here is enough to redirect them.
        // Everything else about the registration (snake_case naming,
        // schema-qualified migrations history table, and the
        // FileChangeInterceptor wiring) stays exactly what production wires
        // in DependencyInjection.cs. The merged host migrates all four
        // contexts on startup, so all four must point here, not just FileDb.
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:AuthDb"] = _postgres.GetConnectionString() + ";Search Path=auth",
            ["ConnectionStrings:FileDb"] = _postgres.GetConnectionString() + ";Search Path=files",
            ["ConnectionStrings:StorageDb"] = _postgres.GetConnectionString() + ";Search Path=storage",
            ["ConnectionStrings:SyncDb"] = _postgres.GetConnectionString() + ";Search Path=sync",
        }));

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

            services.PostConfigure<ZDrive.Shared.Auth.ShareDownloadGrantOptions>(
                options => options.DownloadGrantKey = TestShareGrantKey);
        });
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
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

    /// <summary>
    /// Mints a JWT for an arbitrary (userId, tenantId), signed with this
    /// factory's key. Public so a test can attach it to a client created
    /// from a DERIVED host (via WithWebHostBuilder) — that derived host
    /// still validates against this same instance's signing key, since
    /// WithWebHostBuilder reuses this factory's ConfigureWebHost rather than
    /// constructing a new one.
    /// </summary>
    public string CreateTestToken(Guid userId, Guid tenantId) => GenerateTestToken(userId, tenantId);

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
