// Each service's Api project declares its own top-level "Program" class in
// the global namespace (needed for WebApplicationFactory<Program>).
// Referencing all three Api assemblies unaliased would make "Program"
// ambiguous, so two of them are pulled in under an alias (see the .csproj).
extern alias FileApi;
extern alias StorageApi;

using Azure.Storage;
using Azure.Storage.Blobs;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.Shared.Auth;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;
using FileDbContext = ZDrive.FileService.Infrastructure.Persistence.FileDbContext;
using StorageDbContext = ZDrive.StorageService.Infrastructure.Persistence.StorageDbContext;

namespace ZDrive.BackupCli.Tests.Integration;

/// <summary>
/// Hosts AuthService, FileService and StorageService together in-process
/// (one Postgres container per service + one shared Azurite, via
/// Testcontainers) so the backup CLI can be exercised through the exact
/// multi-service flow it uses in production: real login, real file-node
/// creation, real chunked upload.
///
/// Each service gets its own Postgres container rather than one shared
/// database — EF Core's EnsureCreatedAsync only creates tables the first
/// time a physical database has none at all, so sharing one database across
/// three DbContexts would silently skip creating two of the three schemas.
///
/// There is no real API Gateway here — BackupCliGatewayHandler (see that
/// file) routes by URL path prefix instead, which is enough to reproduce the
/// gateway's contract without standing up YARP.
/// </summary>
public sealed class BackupCliEnvironment : IAsyncLifetime
{
    private readonly string _devKeyDir = Directory.CreateTempSubdirectory("zdrive-backup-cli-jwt-").FullName;

    private readonly PostgreSqlContainer _authPostgres = CreatePostgres();
    private readonly PostgreSqlContainer _filePostgres = CreatePostgres();
    private readonly PostgreSqlContainer _storagePostgres = CreatePostgres();

    private static PostgreSqlContainer CreatePostgres() => new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    private readonly IContainer _azurite = new ContainerBuilder()
        .WithImage("mcr.microsoft.com/azure-storage/azurite")
        .WithPortBinding(10000, true)
        .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(10000))
        .Build();

    public WebApplicationFactory<Program> AuthFactory { get; }
    public WebApplicationFactory<FileApi::Program> FileFactory { get; }
    public WebApplicationFactory<StorageApi::Program> StorageFactory { get; }

    public BackupCliEnvironment()
    {
        // All three hosts run in Development and fall back to
        // DevJwtKeyProvider; pointing them at one temp dir (instead of the
        // real machine's ~/.zdrive/dev-keys) makes them share a signing key
        // with each other and isolates the test run from any local state.
        Environment.SetEnvironmentVariable(DevJwtKeyProvider.KeyDirEnvVar, _devKeyDir);

        AuthFactory = new WebApplicationFactory<Program>().WithWebHostBuilder(ConfigureAuth);
        FileFactory = new WebApplicationFactory<FileApi::Program>().WithWebHostBuilder(ConfigureFile);
        StorageFactory = new WebApplicationFactory<StorageApi::Program>().WithWebHostBuilder(ConfigureStorage);
    }

    public async Task InitializeAsync()
    {
        await Task.WhenAll(
            _authPostgres.StartAsync(),
            _filePostgres.StartAsync(),
            _storagePostgres.StartAsync(),
            _azurite.StartAsync());

        await using (var scope = AuthFactory.Services.CreateAsyncScope())
            await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Database.EnsureCreatedAsync();
        await using (var scope = FileFactory.Services.CreateAsyncScope())
            await scope.ServiceProvider.GetRequiredService<FileDbContext>().Database.EnsureCreatedAsync();
        await using (var scope = StorageFactory.Services.CreateAsyncScope())
            await scope.ServiceProvider.GetRequiredService<StorageDbContext>().Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        AuthFactory.Dispose();
        FileFactory.Dispose();
        StorageFactory.Dispose();
        await Task.WhenAll(
            _authPostgres.DisposeAsync().AsTask(),
            _filePostgres.DisposeAsync().AsTask(),
            _storagePostgres.DisposeAsync().AsTask(),
            _azurite.DisposeAsync().AsTask());
        Directory.Delete(_devKeyDir, recursive: true);
    }

    private void ConfigureAuth(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureServices(services =>
        {
            Replace<DbContextOptions<AuthDbContext>>(services);
            services.AddDbContext<AuthDbContext>(o =>
                o.UseNpgsql(_authPostgres.GetConnectionString() + ";Search Path=auth"));
        });
    }

    private void ConfigureFile(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureServices(services =>
        {
            Replace<DbContextOptions<FileDbContext>>(services);
            services.AddDbContext<FileDbContext>(o =>
                o.UseNpgsql(_filePostgres.GetConnectionString() + ";Search Path=files").UseSnakeCaseNamingConvention());
        });
    }

    private void ConfigureStorage(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureServices(services =>
        {
            // Unlike Auth/File, StorageDbContext has no HasDefaultSchema —
            // it relies on the connection's search_path, which must already
            // exist. A fresh test database only has "public" (matches
            // StorageService.Tests' own factory), so no override here.
            Replace<DbContextOptions<StorageDbContext>>(services);
            services.AddDbContext<StorageDbContext>(o =>
                o.UseNpgsql(_storagePostgres.GetConnectionString()));

            Replace<BlobServiceClient>(services);
            Replace<StorageSharedKeyCredential>(services);
            Replace<IBlobStorageService>(services);

            var blobServiceClient = new BlobServiceClient(AzuriteConnectionString);
            var sharedKeyCredential = new StorageSharedKeyCredential(
                "devstoreaccount1",
                "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==");
            services.AddSingleton(blobServiceClient);
            services.AddSingleton(sharedKeyCredential);
            services.AddSingleton<IBlobStorageService, AzureBlobStorageService>();
        });
    }

    private string AzuriteConnectionString =>
        "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;" +
        "AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;" +
        $"BlobEndpoint=http://{_azurite.Hostname}:{_azurite.GetMappedPublicPort(10000)}/devstoreaccount1;";

    private static void Replace<T>(IServiceCollection services)
    {
        var descriptors = services.Where(d => d.ServiceType == typeof(T)).ToList();
        foreach (var descriptor in descriptors)
            services.Remove(descriptor);
    }
}
