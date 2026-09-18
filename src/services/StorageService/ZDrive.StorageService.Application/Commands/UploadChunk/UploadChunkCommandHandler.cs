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

        if (request.ExpectedTenantId is not null
            && (session.TenantId != request.ExpectedTenantId
                || session.UserId != request.ExpectedUserId
                || session.FileId != request.ExpectedFileId))
        {
            throw new NotFoundException("UploadSession", request.SessionId);
        }

        if (request.ChunkIndex >= session.TotalChunks)
            throw new ConflictException($"Chunk index {request.ChunkIndex} exceeds total chunks {session.TotalChunks}.");

        // Cumulative check BEFORE the bytes are written, under the same row
        // lock UploadedChunks already relies on, so two chunks of one
        // session uploaded concurrently can't both pass the check and then
        // together exceed MaxBytes.
        if (session.MaxBytes is { } maxBytes)
        {
            var newTotal = session.ReceivedBytes + (request.ChunkSizeBytes ?? 0);
            if (newTotal > maxBytes)
                throw new QuotaExceededException(maxBytes, newTotal);

            session.ReceivedBytes = newTotal;
        }

        await _blobStorage.UploadChunkToTempAsync(session.Id, request.ChunkIndex, request.Stream, cancellationToken);

        session.UploadedChunks++;
        await _db.SaveChangesAsync(cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        return new ChunkUploadResultDto(session.Id, request.ChunkIndex, request.ChunkHash, Accepted: true);
    }
}
