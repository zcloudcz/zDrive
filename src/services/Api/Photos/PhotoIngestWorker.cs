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
/// Drives <see cref="PhotoIngestPump"/> forever with two independent loops, each
/// with its own failure handling so one stage failing never stops the other:
///  - reconcile: bootstraps a fresh cursor from current file state (files
///    uploaded before the change log existed are not in it), then follows the
///    change log. Runs again immediately only while the previous round reported
///    more work; otherwise it waits <c>PollIntervalSeconds</c> — the global feed
///    read takes a table-level SHARE lock, so it must not run per claimed photo.
///  - processing: <c>MaxConcurrentProcessing</c> workers, each claiming one photo
///    at a time, so a slow image never holds back the others.
/// Backfill is therefore bounded by BatchSize per feed/bootstrap page and
/// MaxConcurrentProcessing images in flight.
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
        var claimPoll = TimeSpan.FromSeconds(Math.Min(2, poll.TotalSeconds));

        var loops = new List<Task> { RunAsync("reconcile", poll, () => _pump.ReconcileOnceAsync(stoppingToken), stoppingToken) };
        for (var i = 0; i < Math.Max(1, _options.MaxConcurrentProcessing); i++)
            loops.Add(RunAsync("processing", claimPoll, () => _pump.ProcessNextAsync(stoppingToken), stoppingToken));

        await Task.WhenAll(loops);
    }

    /// <param name="round">Returns true when there is more work and the next round should start immediately.</param>
    private async Task RunAsync(string name, TimeSpan idleDelay, Func<Task<bool>> round, CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var moreWork = false;
            try
            {
                moreWork = await round();
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                // Never let a loop die: log and back off until the next poll.
                _logger.LogError(ex, "Photo ingest {Loop} round failed", name);
            }

            if (!moreWork)
            {
                try { await Task.Delay(idleDelay, stoppingToken); }
                catch (OperationCanceledException) { return; }
            }
        }
    }
}
