using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.AuthService.Tests.Fakes;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Tests.Integration;

/// <summary>
/// Factory with Entra:Enabled=true and the real (network-calling)
/// IEntraTokenValidator swapped for a fake the tests control per call.
/// </summary>
public sealed class EntraEnabledFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    public MutableFakeEntraTokenValidator FakeValidator { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Entra:Enabled"] = "true",
                ["Entra:TenantId"] = "test-tenant",
                ["Entra:Audience"] = "test-audience",
                ["Entra:RequiredScope"] = "access_as_user"
            });
        });

        builder.ConfigureServices(services =>
        {
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AuthDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            services.AddDbContext<AuthDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString() + ";Search Path=auth",
                    npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "auth")));

            // Real validator fetches signing keys over the network — replace it
            // with a fake the tests drive directly.
            services.RemoveAll<IEntraTokenValidator>();
            services.AddSingleton<IEntraTokenValidator>(FakeValidator);
        });
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        await db.Database.MigrateAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await _postgres.DisposeAsync();
    }
}

[Trait("Category", "Integration")]
public sealed class EntraExchangeEnabledTests : IClassFixture<EntraEnabledFactory>
{
    private readonly EntraEnabledFactory _factory;
    private readonly HttpClient _client;

    public EntraExchangeEnabledTests(EntraEnabledFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task EntraExchange_HappyPath_ReturnsTokensThatWorkOnProtectedEndpoint()
    {
        _factory.FakeValidator.ExceptionToThrow = null;
        _factory.FakeValidator.IdentityToReturn = new EntraIdentity(
            "test-tenant", Guid.NewGuid().ToString(), "entra-user@example.com", "Entra User");

        var response = await _client.PostAsJsonAsync("/api/v1/auth/entra", new { accessToken = "whatever" });
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var result = await response.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>();
        result!.Success.Should().BeTrue();
        result.Data!.AccessToken.Should().NotBeNullOrWhiteSpace();

        var profileRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/users/me");
        profileRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.Data.AccessToken);
        var profileResponse = await _client.SendAsync(profileRequest);
        profileResponse.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task EntraExchange_ValidatorThrows_ReturnsForbidden()
    {
        _factory.FakeValidator.IdentityToReturn = null;
        _factory.FakeValidator.ExceptionToThrow = new ForbiddenException("bad token");

        var response = await _client.PostAsJsonAsync("/api/v1/auth/entra", new { accessToken = "bad" });

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }
}

[Trait("Category", "Integration")]
public sealed class EntraExchangeDisabledTests : IClassFixture<AuthServiceFactory>
{
    private readonly HttpClient _client;

    public EntraExchangeDisabledTests(AuthServiceFactory factory) => _client = factory.CreateClient();

    [Fact]
    public async Task EntraExchange_WhenDisabled_Returns404()
    {
        // AuthServiceFactory boots off the plain appsettings.json, where
        // Entra:Enabled defaults to false.
        var response = await _client.PostAsJsonAsync("/api/v1/auth/entra", new { accessToken = "irrelevant" });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
