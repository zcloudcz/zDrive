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
        var session = await _db.UploadSessions
            .FirstOrDefaultAsync(s => s.Id == request.SessionId, cancellationToken)
            ?? throw new NotFoundException("UploadSession", request.SessionId);

        if (session.Status != UploadSessionStatus.Active)
            throw new ConflictException($"Upload session '{request.SessionId}' is not active (status: {session.Status}).");

        if (session.ExpiresAt < DateTime.UtcNow)
        {
            session.Status = UploadSessionStatus.Expired;
            await _db.SaveChangesAsync(cancellationToken);
            throw new ConflictException($"Upload session '{request.SessionId}' has expired.");
        }

        // Verify all chunks are uploaded by checking temp storage
        for (var i = 0; i < session.TotalChunks; i++)
        {
            var exists = await _blobStorage.TempChunkExistsAsync(session.Id, i, cancellationToken);
            if (!exists)
                throw new ConflictException($"Chunk {i} is missing. Upload all {session.TotalChunks} chunks before completing.");
        }

        // Move all chunks from temp to final location and collect metadata
        var chunks = new List<BlobChunk>();
        long totalSize = 0;

        for (var i = 0; i < session.TotalChunks; i++)
        {
            var chunkSize = await _blobStorage.GetTempChunkSizeAsync(session.Id, i, cancellationToken);
            var chunkHash = $"chunk-{i:D6}";
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
            totalSize += chunkSize;
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

        await _blobStorage.UploadManifestAsync(session.TenantId, session.UserId, session.FileId, manifest, cancellationToken);

        // Persist chunk records
        foreach (var chunk in chunks)
            _db.BlobChunks.Add(chunk);

        session.Status = UploadSessionStatus.Completed;
        await _db.SaveChangesAsync(cancellationToken);

        // Compute manifest hash
        var manifestJson = JsonSerializer.Serialize(manifest);
        var manifestHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(manifestJson))).ToLowerInvariant();

        var basePath = $"{session.TenantId}/{session.UserId}/files/{session.FileId}";
        return new UploadCompleteDto(basePath, manifestHash, totalSize);
    }
}
