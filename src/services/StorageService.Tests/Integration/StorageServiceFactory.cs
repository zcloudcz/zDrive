using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Azure.Storage;
using Azure.Storage.Blobs;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Infrastructure.BlobStorage;
using ZDrive.StorageService.Infrastructure.Persistence;

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

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureServices(services =>
        {
            // Remove real DbContext
            var dbDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<StorageDbContext>));
            if (dbDescriptor is not null)
                services.Remove(dbDescriptor);

            services.AddDbContext<StorageDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString()));

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

    public async Task InitializeAsync()
    {
        await Task.WhenAll(
            _postgres.StartAsync(),
            _azurite.StartAsync());

        // Apply migrations / create schema
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<StorageDbContext>();
        await db.Database.EnsureCreatedAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await Task.WhenAll(
            _postgres.DisposeAsync().AsTask(),
            _azurite.DisposeAsync().AsTask());
    }
}
