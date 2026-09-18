using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Entities;
using ZDrive.StorageService.Domain.Enums;

namespace ZDrive.StorageService.Application.Commands.InitUpload;

public sealed class InitUploadCommandHandler : IRequestHandler<InitUploadCommand, UploadSessionDto>
{
    private readonly IStorageDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public InitUploadCommandHandler(IStorageDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    public async Task<UploadSessionDto> Handle(InitUploadCommand request, CancellationToken cancellationToken)
    {
        UploadSession session;

        // Bound unreceipted shared uploads to roughly one owner-quota's worth
        // per day: StorageService cannot see FileService's per-user quota (a
        // Write-link holder can grant → init → chunks → complete in a loop
        // without ever calling FileService's versions endpoint, and those
        // promoted-but-unreceipted chunks are invisible to the quota sum
        // FileService computes over file_versions — nothing garbage-collects
        // them yet, see docs/superpowers/specs/2026-09-18-subscription-plans-design.md
        // "Blob GC"). The grant carries the owner's headroom at mint time;
        // this sums MaxBytes of the owner's other OPEN shared sessions from
        // the last 24h so a burst of grants can't multiply past it — a
        // Completed session's bytes are already counted by the real quota
        // once its receipt lands, and an Expired/Aborted one holds no bytes
        // at all, so counting either would refuse a legitimate uploader for
        // no reason (only "Active" — still open, quota-blind — is the
        // budget this exists to bound).
        if (request.IsShared && request.MaxBytes is { } maxBytes && request.QuotaRemainingBytes is { } remaining)
        {
            // The check (SUM) and the insert that grows the sum must happen
            // as one atomic step, or two concurrent inits for the same owner
            // can both read the same SUM before either's row is visible to
            // the other and both pass a check only one of them should have.
            // Transaction-scoped advisory lock keyed per owner serializes
            // that pair without taking a row lock on rows that may not exist
            // yet.
            await using var budgetLock = await _db.LockOwnerSharedUploadBudgetAsync(
                request.TenantId, request.UserId, cancellationToken);

            var cutoff = DateTime.UtcNow.AddHours(-24);
            var inFlight = await _db.UploadSessions
                .Where(s => s.TenantId == request.TenantId && s.UserId == request.UserId && s.IsShared
                    && s.CreatedAt >= cutoff && s.Status == UploadSessionStatus.Active)
                .SumAsync(s => (long?)s.MaxBytes ?? 0, cancellationToken);

            if (inFlight + maxBytes > remaining)
                throw new QuotaExceededException(remaining, inFlight + maxBytes);

            session = BuildSession(request);
            _db.UploadSessions.Add(session);
            await _db.SaveChangesAsync(cancellationToken);
            await budgetLock.CommitAsync(cancellationToken);
        }
        else
        {
            session = BuildSession(request);
            _db.UploadSessions.Add(session);
            await _db.SaveChangesAsync(cancellationToken);
        }

        var sasUrl = _blobStorage.GenerateTempUploadSasUrl(session.Id, 0);

        return new UploadSessionDto(session.Id, sasUrl);
    }

    private static UploadSession BuildSession(InitUploadCommand request) => new()
    {
        Id = Guid.NewGuid(),
        UserId = request.UserId,
        TenantId = request.TenantId,
        FileId = request.FileId,
        FileName = request.FileName,
        Status = UploadSessionStatus.Active,
        TotalChunks = request.TotalChunks,
        UploadedChunks = 0,
        CreatedAt = DateTime.UtcNow,
        ExpiresAt = DateTime.UtcNow.AddHours(24),
        MaxBytes = request.MaxBytes,
        IsShared = request.IsShared
    };
}
