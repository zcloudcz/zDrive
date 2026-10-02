using System.IdentityModel.Tokens.Jwt;
using Azure.Storage;
using Azure.Storage.Blobs;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using Microsoft.EntityFrameworkCore;
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
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.PhotoService.Domain.Enums;
using ZDrive.Api.Photos;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.PhotoService.Infrastructure.Ingest;
using ZDrive.PhotoService.Infrastructure.Persistence;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;
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

    private readonly IContainer _azurite = new ContainerBuilder()
        .WithImage("mcr.microsoft.com/azure-storage/azurite")
        .WithPortBinding(10000, true)
        .WithPortBinding(10001, true)
        .WithPortBinding(10002, true)
        .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(10000))
        .Build();

    private const string AzuriteAccountKey =
        "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==";

    private string AzuriteConnectionString =>
        $"DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey={AzuriteAccountKey};BlobEndpoint=http://{_azurite.Hostname}:{_azurite.GetMappedPublicPort(10000)}/devstoreaccount1;";

    /// <summary>While set, thumbnail writes throw — simulates a transient blob failure.</summary>
    public bool FailThumbnailWrites { get; set; }

    /// <summary>Awaited (with the thumbnail version) before every thumbnail write; lets a test pause one worker.</summary>
    public Func<string, Task>? BeforeThumbnailWrite { get; set; }

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

            // Real Azurite instead of the dev-storage default.
            RemoveService<BlobServiceClient>(services);
            RemoveService<StorageSharedKeyCredential>(services);
            RemoveService<IBlobStorageService>(services);
            services.AddSingleton(new BlobServiceClient(AzuriteConnectionString));
            services.AddSingleton(new StorageSharedKeyCredential("devstoreaccount1", AzuriteAccountKey));
            services.AddSingleton<IBlobStorageService, AzureBlobStorageService>();

            // Same port, but thumbnail writes can be made to fail on demand.
            services.AddScoped<IThumbnailStore>(sp => new FlakyThumbnailStore(
                sp.GetRequiredService<StorageServicePhotoAccess>(), () => FailThumbnailWrites, () => BeforeThumbnailWrite));
        });

        // The merged host migrates all five contexts on startup. They share one
        // database (ZDriveDb); each model and migration names its own schema.
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:ZDriveDb"] = _postgres.GetConnectionString(),
            // Tests drive the pump deterministically instead of racing the background loop.
            ["Photos:Ingest:Enabled"] = "false",
        }));
    }

    public async Task InitializeAsync()
    {
        await Task.WhenAll(_postgres.StartAsync(), _azurite.StartAsync());
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
            await Task.WhenAll(_postgres.DisposeAsync().AsTask(), _azurite.DisposeAsync().AsTask());
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

    /// <summary>
    /// Seeds a photo row directly. Photos are only ever created by the ingest
    /// pipeline (no public API creates one), so tests seed the row itself.
    /// </summary>
    public async Task<PhotoDto> SeedPhotoAsync(
        string fileName = "photo.jpg", Guid? userId = null, Guid? tenantId = null)
    {
        var photo = new Photo
        {
            Id = Guid.NewGuid(),
            FileId = Guid.NewGuid(),
            UserId = userId ?? TestUserId,
            TenantId = tenantId ?? TestTenantId,
            OriginalFileName = fileName,
            BlobPath = $"/tenant/user/{fileName}",
            ProcessingStatus = ProcessingStatus.Processed,
        };
        await SeedAsync(async db =>
        {
            db.Photos.Add(photo);
            await db.SaveChangesAsync();
        });
        return photo.ToDto();
    }

    private static void RemoveService<T>(IServiceCollection services)
    {
        foreach (var descriptor in services.Where(d => d.ServiceType == typeof(T)).ToList())
            services.Remove(descriptor);
    }

    /// <summary>
    /// Ages every change-log row past the feed's 5 s hold-back (occurred_at is
    /// stamped by the database clock, so this is a plain UPDATE — same
    /// technique as FileChangeFeedTests) and runs both pump stages to idle.
    /// </summary>
    public async Task DrainIngestAsync()
    {
        await AgeChangesAsync();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        await Services.GetRequiredService<PhotoIngestPump>().DrainAsync(cts.Token);
    }

    public async Task AgeChangesAsync()
    {
        using var scope = Services.CreateScope();
        var files = scope.ServiceProvider.GetRequiredService<FileDbContext>();
        await files.Database.ExecuteSqlRawAsync(
            "UPDATE files.file_changes SET occurred_at = occurred_at - interval '10 seconds' WHERE occurred_at > now() - interval '5 seconds'");
    }

    /// <summary>Reads the photo row (hidden or not) for a file, straight from the database.</summary>
    public async Task<Photo?> FindPhotoByFileAsync(Guid fileId)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        return await db.Photos.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(p => p.FileId == fileId);
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
