using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Commands.DeleteBlob;

public sealed class DeleteBlobCommandHandler : IRequestHandler<DeleteBlobCommand, bool>
{
    private readonly IStorageDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public DeleteBlobCommandHandler(IStorageDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    public async Task<bool> Handle(DeleteBlobCommand request, CancellationToken cancellationToken)
    {
        // Delete from blob storage
        await _blobStorage.DeleteFileAsync(request.TenantId, request.UserId, request.FileId, cancellationToken);

        // Delete chunk records from DB
        var chunks = await _db.BlobChunks
            .Where(c => c.FileId == request.FileId)
            .ToListAsync(cancellationToken);

        if (chunks.Count > 0)
        {
            _db.BlobChunks.RemoveRange(chunks);
            await _db.SaveChangesAsync(cancellationToken);
        }

        return true;
    }
}
