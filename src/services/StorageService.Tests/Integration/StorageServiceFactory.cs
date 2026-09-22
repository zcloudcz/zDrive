using System.Security.Cryptography;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Azure.Storage;
using Azure.Storage.Blobs;
using Microsoft.IdentityModel.Tokens;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;

namespace ZDrive.StorageService.Tests.Integration;

public sealed class StorageServiceFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    private readonly IContainer _azurite = new ContainerBuilder()
        .WithImage("mcr.microsoft.com/azure-storage/azurite")
        .WithPortBinding(10000, true)
        .WithPortBinding(10001, true)
        .WithPortBinding(10002, true)
        .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(10000))
        .Build();

    public string AzuriteConnectionString => $"DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://{_azurite.Hostname}:{_azurite.GetMappedPublicPort(10000)}/devstoreaccount1;";

    // Created eagerly so it exists before the host is built; tests sign JWTs
    // with this key and the service is configured to validate against it.
    public RSA Rsa { get; } = RSA.Create(2048);

    // Generated at runtime (not a literal) so nothing here looks like a
    // committed secret to the repo's gitleaks scan. SharedDownloadFlowTests
    // mints grants with this same key and validates them against this same
    // factory, all within this one process — no other test host needs to
    // agree on it.
    public static readonly string TestShareGrantKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

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

            services.PostConfigure<ZDrive.Shared.Auth.ShareDownloadGrantOptions>(
                options => options.DownloadGrantKey = TestShareGrantKey);
        });

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

        builder.ConfigureServices(services =>
        {
            // Remove real blob storage services
            RemoveService<BlobServiceClient>(services);
            RemoveService<StorageSharedKeyCredential>(services);
            RemoveService<IBlobStorageService>(services);

            // Register Azurite-backed blob storage
            var connectionString = AzuriteConnectionString;
            var blobServiceClient = new BlobServiceClient(connectionString);
            var sharedKeyCredential = new StorageSharedKeyCredential(
                "devstoreaccount1",
                "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==");

            services.AddSingleton(blobServiceClient);
            services.AddSingleton(sharedKeyCredential);
            services.AddSingleton<IBlobStorageService, AzureBlobStorageService>();
        });
    }

    private static void RemoveService<T>(IServiceCollection services)
    {
        var descriptors = services.Where(d => d.ServiceType == typeof(T)).ToList();
        foreach (var descriptor in descriptors)
            services.Remove(descriptor);
    }

    /// <summary>
    /// Creates a JWT signed with this factory's key, valid for the service under test.
    /// </summary>
    public string CreateAccessToken(Guid userId, Guid tenantId)
    {
        var credentials = new SigningCredentials(new RsaSecurityKey(Rsa), SecurityAlgorithms.RsaSha256);

        var claims = new[]
        {
            new System.Security.Claims.Claim("sub", userId.ToString()),
            new System.Security.Claims.Claim("tenant_id", tenantId.ToString()),
            new System.Security.Claims.Claim("role", "Owner"),
            new System.Security.Claims.Claim("display_name", "Test User")
        };

        var token = new System.IdentityModel.Tokens.Jwt.JwtSecurityToken(
            issuer: "zdrive",
            audience: "zdrive-api",
            claims: claims,
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: credentials);

        return new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler().WriteToken(token);
    }

    public async Task InitializeAsync()
    {
        await Task.WhenAll(
            _postgres.StartAsync(),
            _azurite.StartAsync());
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        Rsa.Dispose();
        await Task.WhenAll(
            _postgres.DisposeAsync().AsTask(),
            _azurite.DisposeAsync().AsTask());
    }
}
