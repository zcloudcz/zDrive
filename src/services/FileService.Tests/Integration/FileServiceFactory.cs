using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
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

    private RSA _rsa = null!;

    public Guid TestUserId { get; } = Guid.NewGuid();
    public Guid TestTenantId { get; } = Guid.NewGuid();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureServices(services =>
        {
            // Remove the real DbContext registration
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<FileDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            // Register DbContext pointing to testcontainer
            services.AddDbContext<FileDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString() + ";Search Path=files"));
        });
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        _rsa = RSA.Create(2048);

        // Apply migrations / create schema
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FileDbContext>();
        await db.Database.EnsureCreatedAsync();
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
