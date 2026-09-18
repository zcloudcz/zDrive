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

        // Both directions of the shared/authenticated split: a shared-flow
        // caller (ExpectedTenantId set) must find IsShared==true with a
        // matching owner, and an authenticated caller (no Expected* — the
        // pre-existing StorageController never set them) must not silently
        // touch a session it did not create via its own JWT-bound init.
        var isSharedCall = request.ExpectedTenantId is not null;
        if (session.IsShared != isSharedCall
            || (isSharedCall
                && (session.TenantId != request.ExpectedTenantId
                    || session.UserId != request.ExpectedUserId
                    || session.FileId != request.ExpectedFileId)))
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
