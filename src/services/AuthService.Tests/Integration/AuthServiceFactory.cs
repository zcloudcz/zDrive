using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.AuthService.Infrastructure.Persistence;

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

        builder.ConfigureServices(services =>
        {
            // Remove the real DbContext registration
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AuthDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            // Register DbContext pointing to testcontainer
            // MigrationsHistoryTable must be schema-qualified here too (matching
            // DependencyInjection.cs) — otherwise it falls back to the connection's
            // search_path, which points at a schema that doesn't exist until the
            // first migration creates it, and Migrate() fails before it gets there.
            services.AddDbContext<AuthDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString() + ";Search Path=auth",
                    npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "auth")));
        });
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        // Apply migrations
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        await db.Database.MigrateAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await _postgres.DisposeAsync();
    }
}
