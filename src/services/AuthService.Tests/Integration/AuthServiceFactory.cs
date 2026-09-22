using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Testcontainers.PostgreSql;
using Xunit;

namespace ZDrive.AuthService.Tests.Integration;

public sealed class AuthServiceFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        // The merged host migrates all four contexts on startup, so all four
        // connection strings must point at this factory's single Postgres
        // container (each context's own schema, matching DependencyInjection.cs).
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:AuthDb"] = _postgres.GetConnectionString() + ";Search Path=auth",
            ["ConnectionStrings:FileDb"] = _postgres.GetConnectionString() + ";Search Path=files",
            ["ConnectionStrings:StorageDb"] = _postgres.GetConnectionString() + ";Search Path=storage",
            ["ConnectionStrings:SyncDb"] = _postgres.GetConnectionString() + ";Search Path=sync",
        }));
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await _postgres.DisposeAsync();
    }
}
