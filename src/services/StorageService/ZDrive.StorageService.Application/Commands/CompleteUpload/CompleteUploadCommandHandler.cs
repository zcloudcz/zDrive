using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Entities;
using ZDrive.StorageService.Domain.Enums;
using ZDrive.StorageService.Domain.ValueObjects;
using ZDrive.Shared.Exceptions;

namespace ZDrive.StorageService.Application.Commands.CompleteUpload;

public sealed class CompleteUploadCommandHandler : IRequestHandler<CompleteUploadCommand, UploadCompleteDto>
{
    private readonly IStorageDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public CompleteUploadCommandHandler(IStorageDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    public async Task<UploadCompleteDto> Handle(CompleteUploadCommand request, CancellationToken cancellationToken)
    {
        await using var transaction = await _db.LockUploadSessionAsync(request.SessionId, cancellationToken);

        var session = await _db.UploadSessions
            .FirstOrDefaultAsync(s => s.Id == request.SessionId, cancellationToken)
            ?? throw new NotFoundException("UploadSession", request.SessionId);

        if (session.IsShared != request.IsShared
            || session.TenantId != request.CallerTenantId
            || session.UserId != request.CallerUserId
            || (request.IsShared && session.FileId != request.ExpectedFileId))
        {
            throw new NotFoundException("UploadSession", request.SessionId);
        }

        if (session.Status != UploadSessionStatus.Active)
            throw new ConflictException($"Upload session '{request.SessionId}' is not active (status: {session.Status}).");

        if (session.ExpiresAt < DateTime.UtcNow)
        {
            session.Status = UploadSessionStatus.Expired;
            await _db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            throw new ConflictException($"Upload session '{request.SessionId}' has expired.");
        }

        // Verify all chunks are uploaded by checking temp storage
        for (var i = 0; i < session.TotalChunks; i++)
        {
            var exists = await _blobStorage.TempChunkExistsAsync(session.Id, i, cancellationToken);
            if (!exists)
                throw new ConflictException($"Chunk {i} is missing. Upload all {session.TotalChunks} chunks before completing.");
        }

        // Read the actually-stored size of every chunk BEFORE moving anything,
        // so an over-cap upload can be rejected without promoting any bytes
        // to final storage (chunk-level PUT already enforces MaxBytes
        // per-chunk, but that only catches the total growing chunk by chunk —
        // it can't see a session whose cap changed, or verify the whole sum
        // one more time before it becomes permanent).
        var chunkSizes = new long[session.TotalChunks];
        long totalSize = 0;
        for (var i = 0; i < session.TotalChunks; i++)
        {
            chunkSizes[i] = await _blobStorage.GetTempChunkSizeAsync(session.Id, i, cancellationToken);
            totalSize += chunkSizes[i];
        }

        if (session.MaxBytes is { } maxBytes && totalSize > maxBytes)
        {
            await _blobStorage.DeleteTempUploadAsync(session.Id, cancellationToken);
            session.Status = UploadSessionStatus.Aborted;
            await _db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            throw new QuotaExceededException(maxBytes, totalSize);
        }

        // Move all chunks from temp to final location and collect metadata
        var chunks = new List<BlobChunk>();

        for (var i = 0; i < session.TotalChunks; i++)
        {
            var chunkSize = chunkSizes[i];

            // Content-addressed chunk name: identical content lands on the same
            // blob path, so re-uploads never destroy chunks an older file
            // version still references (and identical chunks dedupe for free).
            var chunkHash = await _blobStorage.ComputeTempChunkHashAsync(session.Id, i, cancellationToken);
            var blobPath = await _blobStorage.MoveChunkToFinalAsync(
                session.Id, i, session.TenantId, session.UserId, session.FileId, chunkHash, cancellationToken);

            var chunk = new BlobChunk
            {
                Id = Guid.NewGuid(),
                FileId = session.FileId,
                ChunkHash = chunkHash,
                ChunkIndex = i,
                SizeBytes = chunkSize,
                BlobPath = blobPath,
                CreatedAt = DateTime.UtcNow
            };

            chunks.Add(chunk);
        }

        // Build and upload manifest
        var manifest = new ChunkManifest
        {
            FileId = session.FileId,
            TotalSize = totalSize,
            Chunks = chunks.Select(c => new ChunkInfo
            {
                Hash = c.ChunkHash,
                Index = c.ChunkIndex,
                Size = c.SizeBytes
            }).ToList()
        };

        // Manifest hash identifies this version — compute it up front so the
        // immutable snapshot can be stored under its content address.
        var manifestJson = JsonSerializer.Serialize(manifest);
        var manifestHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(manifestJson))).ToLowerInvariant();

        await _blobStorage.UploadManifestAsync(session.TenantId, session.UserId, session.FileId, manifest, cancellationToken);
        await _blobStorage.UploadManifestSnapshotAsync(
            session.TenantId, session.UserId, session.FileId, manifestHash, manifest, cancellationToken);

        // Persist chunk records. Chunks are content-addressed, so skip hashes
        // this file already knows (re-upload of identical content) and dedupe
        // within the current upload.
        var newHashes = chunks.Select(c => c.ChunkHash).ToList();
        var knownHashes = await _db.BlobChunks
            .Where(c => c.FileId == session.FileId && newHashes.Contains(c.ChunkHash))
            .Select(c => c.ChunkHash)
            .ToListAsync(cancellationToken);

        foreach (var chunk in chunks.DistinctBy(c => c.ChunkHash).Where(c => !knownHashes.Contains(c.ChunkHash)))
            _db.BlobChunks.Add(chunk);

        session.Status = UploadSessionStatus.Completed;
        await _db.SaveChangesAsync(cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        var basePath = $"{session.TenantId}/{session.UserId}/files/{session.FileId}";
        return new UploadCompleteDto(basePath, manifestHash, totalSize);
    }
}
