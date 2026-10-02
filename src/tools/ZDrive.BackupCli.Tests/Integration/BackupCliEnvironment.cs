using Azure.Storage;
using Azure.Storage.Blobs;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.Shared.Auth;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;

namespace ZDrive.BackupCli.Tests.Integration;

/// <summary>
/// Hosts the merged Api (Auth + File + Storage + Sync, one Postgres
/// container + one shared Azurite, via Testcontainers) so the backup CLI can
/// be exercised through the exact flow it uses in production: real login,
/// real file-node creation, real chunked upload.
///
/// There is no real API Gateway here — BackupCliGatewayHandler (see that
/// file) forwards straight to this one host, which is enough to reproduce
/// the gateway's contract without standing up YARP.
/// </summary>
public sealed class BackupCliEnvironment : IAsyncLifetime
{
    private readonly string _devKeyDir = Directory.CreateTempSubdirectory("zdrive-backup-cli-jwt-").FullName;

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
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

    public WebApplicationFactory<Program> ApiFactory { get; }

    public BackupCliEnvironment()
    {
        // Development fallback to DevJwtKeyProvider; pointing it at one temp
        // dir (instead of the real machine's ~/.zdrive/dev-keys) isolates the
        // test run from any local state.
        Environment.SetEnvironmentVariable(DevJwtKeyProvider.KeyDirEnvVar, _devKeyDir);

        ApiFactory = new WebApplicationFactory<Program>().WithWebHostBuilder(ConfigureApi);
    }

    public async Task InitializeAsync()
    {
        await Task.WhenAll(
            _postgres.StartAsync(),
            _azurite.StartAsync());
    }

    public async Task DisposeAsync()
    {
        ApiFactory.Dispose();
        await Task.WhenAll(
            _postgres.DisposeAsync().AsTask(),
            _azurite.DisposeAsync().AsTask());
        Directory.Delete(_devKeyDir, recursive: true);
    }

    private void ConfigureApi(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        // The merged host migrates all five contexts on startup. They share one
        // database (ZDriveDb); each model and migration names its own schema.
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:ZDriveDb"] = _postgres.GetConnectionString(),
            // The photo ingest worker takes its own SHARE locks on files.file_changes;
            // only PhotoService.Tests exercises it (and drives it manually).
            ["Photos:Ingest:Enabled"] = "false",
        }));

        builder.ConfigureServices(services =>
        {
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
