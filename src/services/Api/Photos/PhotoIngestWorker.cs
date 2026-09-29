using Microsoft.Extensions.Options;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.PhotoService.Application.Options;
using ZDrive.PhotoService.Infrastructure.Ingest;

namespace ZDrive.Api.Photos;

public static class PhotoIngestServiceCollectionExtensions
{
    /// <summary>Wires the Photo module's ports to the File and Storage modules and starts the worker.</summary>
    public static IServiceCollection AddPhotoIngest(this IServiceCollection services)
    {
        services.AddScoped<IFileChangeSource, FileServiceChangeSource>();
        services.AddScoped<StorageServicePhotoAccess>();
        services.AddScoped<IPhotoSourceReader>(sp => sp.GetRequiredService<StorageServicePhotoAccess>());
        services.AddScoped<IThumbnailStore>(sp => sp.GetRequiredService<StorageServicePhotoAccess>());
        services.AddHostedService<PhotoIngestWorker>();
        return services;
    }
}

/// <summary>
/// Drives <see cref="PhotoIngestPump"/> forever. Starts at cursor 0 on a fresh
/// database, so it also backfills photos that existed before it shipped —
/// bounded by <c>Photos:Ingest:BatchSize</c> per feed page and
/// <c>MaxConcurrentProcessing</c> images at a time.
/// </summary>
public sealed class PhotoIngestWorker : BackgroundService
{
    private readonly PhotoIngestPump _pump;
    private readonly PhotoIngestOptions _options;
    private readonly ILogger<PhotoIngestWorker> _logger;

    public PhotoIngestWorker(PhotoIngestPump pump, IOptions<PhotoIngestOptions> options, ILogger<PhotoIngestWorker> logger)
    {
        _pump = pump;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("Photo ingest worker disabled (Photos:Ingest:Enabled = false).");
            return;
        }

        var poll = TimeSpan.FromSeconds(Math.Max(1, _options.PollIntervalSeconds));
        while (!stoppingToken.IsCancellationRequested)
        {
            var idle = true;
            try
            {
                var moreFeed = await _pump.ReconcileOnceAsync(stoppingToken);
                var processed = await _pump.ProcessPendingAsync(stoppingToken);
                idle = !moreFeed && processed == 0;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                // Never let the loop die: log and back off until the next poll.
                _logger.LogError(ex, "Photo ingest round failed");
            }

            if (idle)
            {
                try { await Task.Delay(poll, stoppingToken); }
                catch (OperationCanceledException) { break; }
            }
        }
    }
}
