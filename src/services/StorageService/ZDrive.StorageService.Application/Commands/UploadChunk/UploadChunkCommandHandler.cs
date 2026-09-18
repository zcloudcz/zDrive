using System.Text.Json;
using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.StorageService.Application.Commands.UploadChunk;

public sealed class UploadChunkCommandHandler : IRequestHandler<UploadChunkCommand, ChunkUploadResultDto>
{
    private readonly IStorageDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public UploadChunkCommandHandler(IStorageDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    public async Task<ChunkUploadResultDto> Handle(UploadChunkCommand request, CancellationToken cancellationToken)
    {
        await using var transaction = await _db.LockUploadSessionAsync(request.SessionId, cancellationToken);

        var session = await _db.UploadSessions
            .FirstOrDefaultAsync(s => s.Id == request.SessionId, cancellationToken)
            ?? throw new NotFoundException("UploadSession", request.SessionId);

        if (session.Status == UploadSessionStatus.Expired || session.ExpiresAt < DateTime.UtcNow)
        {
            session.Status = UploadSessionStatus.Expired;
            await _db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            throw new ConflictException($"Upload session '{request.SessionId}' has expired.");
        }

        if (session.Status != UploadSessionStatus.Active)
            throw new ConflictException($"Upload session '{request.SessionId}' is not active (status: {session.Status}).");

        // Ownership check for BOTH flows: an authenticated caller must own
        // the session (tenant/user from its JWT) exactly like a shared
        // caller must own it (tenant/user/file from its grant) — a session
        // belonging to someone else 404s either way. IsShared additionally
        // keeps the two flows from ever reaching each other's sessions even
        // when ids happen to line up (a Write-link grant for file F must not
        // also match the owner's own authenticated session on F).
        if (session.IsShared != request.IsShared
            || session.TenantId != request.CallerTenantId
            || session.UserId != request.CallerUserId
            || (request.IsShared && session.FileId != request.ExpectedFileId))
        {
            throw new NotFoundException("UploadSession", request.SessionId);
        }

        if (request.ChunkIndex >= session.TotalChunks)
            throw new ConflictException($"Chunk index {request.ChunkIndex} exceeds total chunks {session.TotalChunks}.");

        await _blobStorage.UploadChunkToTempAsync(session.Id, request.ChunkIndex, request.Stream, cancellationToken);

        // Checked AFTER the bytes are written, measuring what actually
        // landed (GetTempChunkSizeAsync reads the blob's real length) rather
        // than trusting a client-supplied size: a chunked-transfer-encoding
        // request has no Content-Length at all, so a pre-write check keyed
        // on that header could be bypassed simply by omitting it. Still
        // under the same row lock UploadedChunks already relies on, so two
        // chunks of one session uploaded concurrently can't both pass the
        // check and together exceed MaxBytes. Keyed per chunk index (not a
        // running total) so a legitimate retry of one index replaces its own
        // contribution instead of being counted twice. A chunk that pushes
        // the session over the cap is removed again — the session must never
        // end up holding more than MaxBytes worth of temp data even
        // transiently.
        if (session.MaxBytes is { } maxBytes)
        {
            var chunkSize = await _blobStorage.GetTempChunkSizeAsync(session.Id, request.ChunkIndex, cancellationToken);
            var sizes = DeserializeChunkSizes(session.ChunkSizesJson);
            var newTotal = sizes.Where(kv => kv.Key != request.ChunkIndex).Sum(kv => kv.Value) + chunkSize;

            if (newTotal > maxBytes)
            {
                // ponytail: this deletes whatever is currently stored at
                // this index — including a PREVIOUS, still-valid upload of
                // it, if this PUT is a re-upload that grew (e.g. a client
                // retry sending a different/larger chunk than before).
                // Self-inflicted (the caller changed what it sent for an
                // index it already had accepted) and accounting stays
                // internally consistent (the index just goes back to
                // "nothing uploaded yet"), but it does mean a successful
                // prior chunk can be undone by a later failed one at the
                // same index. Upgrade path: stage the new chunk under a
                // temp name and swap it in only once it's confirmed to fit.
                await _blobStorage.DeleteTempChunkAsync(session.Id, request.ChunkIndex, cancellationToken);
                throw new QuotaExceededException(maxBytes, newTotal);
            }

            sizes[request.ChunkIndex] = chunkSize;
            session.ChunkSizesJson = JsonSerializer.Serialize(sizes);
        }

        session.UploadedChunks++;
        await _db.SaveChangesAsync(cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        return new ChunkUploadResultDto(session.Id, request.ChunkIndex, request.ChunkHash, Accepted: true);
    }

    internal static Dictionary<int, long> DeserializeChunkSizes(string? json) =>
        string.IsNullOrEmpty(json)
            ? new Dictionary<int, long>()
            : JsonSerializer.Deserialize<Dictionary<int, long>>(json) ?? new Dictionary<int, long>();
}
