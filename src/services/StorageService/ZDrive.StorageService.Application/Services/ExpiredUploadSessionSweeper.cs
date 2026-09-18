using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Entities;
using ZDrive.StorageService.Domain.Enums;

namespace ZDrive.StorageService.Application.Services;

/// <summary>
/// Background cleanup for upload sessions that were never completed or
/// aborted and outlived their own ExpiresAt: an anonymous shared-upload
/// caller has no account to hold accountable for cleaning up after itself,
/// so nothing here waits for a client to come back and abort. Deletes the
/// session's temp chunks (the only thing an open session actually holds —
/// a completed session's chunks are already final storage, untouched) and
/// marks it Expired, the same status UploadChunk/CompleteUpload already
/// assign when they notice a session expired mid-request.
///
/// Idempotent: sweeping the same session twice (two instances, or a run
/// overlapping a client's own late request) just deletes an already-empty
/// temp prefix and re-applies the same status — harmless either way.
/// </summary>
public sealed class ExpiredUploadSessionSweeper : BackgroundService
{
    private static readonly TimeSpan InitialDelay = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<ExpiredUploadSessionSweeper> _logger;

    public ExpiredUploadSessionSweeper(IServiceScopeFactory scopeFactory, ILogger<ExpiredUploadSessionSweeper> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    /// <summary>Pure predicate, kept separate from the DB query so it has a Docker-less unit test.</summary>
    public static bool ShouldSweep(UploadSession session, DateTime utcNow) =>
        session.Status == UploadSessionStatus.Active && session.ExpiresAt < utcNow;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await Task.Delay(InitialDelay, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await SweepOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                // Shutdown mid-sweep — end the loop quietly, not as a failure.
                break;
            }
            catch (Exception ex)
            {
                // A whole-sweep failure (e.g. the DB briefly unreachable) must
                // not propagate out of ExecuteAsync: BackgroundService's
                // default StopHostOnBackgroundServiceException behavior would
                // take the entire StorageService down over a cleanup job.
                // Log and try again next interval instead.
                _logger.LogError(ex, "Upload session sweep failed; will retry at the next interval");
            }

            try
            {
                await Task.Delay(Interval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    public async Task SweepOnceAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IStorageDbContext>();
        var blobStorage = scope.ServiceProvider.GetRequiredService<IBlobStorageService>();

        // Filtered in-memory by ShouldSweep rather than in the query itself —
        // "Active" narrows it to a small set server-side, and DateTime
        // comparisons against DateTime.UtcNow translate fine either way, but
        // keeping the actual sweep condition as one testable method avoids
        // ever having two copies of "what counts as expired" drift apart.
        // This first pass is only a candidate list — the authoritative check
        // happens again per session, under its own lock, in SweepSessionAsync.
        var candidateIds = await db.UploadSessions
            .Where(s => s.Status == UploadSessionStatus.Active)
            .Select(s => s.Id)
            .ToListAsync(ct);

        foreach (var sessionId in candidateIds)
        {
            try
            {
                await SweepSessionAsync(db, blobStorage, sessionId, ct);
            }
            catch (Exception ex)
            {
                // One session's failure (e.g. a transient blob storage error)
                // must not stop the sweep of every other expired session.
                _logger.LogError(ex, "Failed to sweep expired upload session {SessionId}", sessionId);
            }
        }
    }

    private static async Task SweepSessionAsync(
        IStorageDbContext db, IBlobStorageService blobStorage, Guid sessionId, CancellationToken ct)
    {
        // Same row lock every write handler takes (LockUploadSessionAsync) —
        // re-checking status/expiry INSIDE it, not trusting the candidate
        // list gathered before the lock, is what stops this from ever
        // sweeping a session another request is concurrently completing:
        // CompleteUpload holds the same lock while it moves chunks to final
        // storage, so this either runs strictly before that (and correctly
        // finds it still Active-and-expired) or strictly after (and finds it
        // Completed, so ShouldSweep says no).
        await using var transaction = await db.LockUploadSessionAsync(sessionId, ct);

        var session = await db.UploadSessions.FirstOrDefaultAsync(s => s.Id == sessionId, ct);
        if (session is null || !ShouldSweep(session, DateTime.UtcNow))
        {
            await transaction.CommitAsync(ct);
            return;
        }

        await blobStorage.DeleteTempUploadAsync(session.Id, ct);
        session.Status = UploadSessionStatus.Expired;
        await db.SaveChangesAsync(ct);

        await transaction.CommitAsync(ct);
    }
}
