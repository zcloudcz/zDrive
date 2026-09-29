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

namespace ZDrive.SyncService.Tests.Integration;

public sealed class SyncServiceFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    // Created eagerly so it exists before the host is built; tests sign JWTs
    // with this key and the service is configured to validate against it.
    public RSA Rsa { get; } = RSA.Create(2048);

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
                options => options.TokenValidationParameters.IssuerSigningKey = new RsaSecurityKey(Rsa));
        });

        // The merged host migrates all five contexts on startup, so all five
        // connection strings must point at this factory's single Postgres
        // container (each context's own schema, matching DependencyInjection.cs).
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:AuthDb"] = _postgres.GetConnectionString() + ";Search Path=auth",
            ["ConnectionStrings:FileDb"] = _postgres.GetConnectionString() + ";Search Path=files",
            ["ConnectionStrings:StorageDb"] = _postgres.GetConnectionString() + ";Search Path=storage",
            ["ConnectionStrings:SyncDb"] = _postgres.GetConnectionString() + ";Search Path=sync",
            ["ConnectionStrings:PhotoDb"] = _postgres.GetConnectionString() + ";Search Path=photos",
        }));
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        Rsa.Dispose();
        await _postgres.DisposeAsync();
    }
}
