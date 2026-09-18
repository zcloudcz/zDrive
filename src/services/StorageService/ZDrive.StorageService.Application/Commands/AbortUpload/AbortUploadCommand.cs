using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Enums;

namespace ZDrive.StorageService.Application.Commands.AbortUpload;

public sealed record AbortUploadCommand(Guid SessionId, Guid UserId, Guid TenantId, Guid? ExpectedFileId = null) : IRequest<bool>;

public sealed class AbortUploadCommandHandler : IRequestHandler<AbortUploadCommand, bool>
{
    private readonly IStorageDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public AbortUploadCommandHandler(IStorageDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    public async Task<bool> Handle(AbortUploadCommand request, CancellationToken cancellationToken)
    {
        await using var transaction = await _db.LockUploadSessionAsync(request.SessionId, cancellationToken);
        var session = await _db.UploadSessions
            .FirstOrDefaultAsync(s => s.Id == request.SessionId, cancellationToken);
        if (session is null)
            return true;
        var isSharedCall = request.ExpectedFileId is not null;
        if (session.IsShared != isSharedCall
            || session.UserId != request.UserId || session.TenantId != request.TenantId
            || (isSharedCall && session.FileId != request.ExpectedFileId))
        {
            throw new NotFoundException("UploadSession", request.SessionId);
        }

        // A completed session stays completed. Only its temporary prefix is cleaned;
        // immutable manifests and content-addressed chunks may back existing versions.
        if (session.Status != UploadSessionStatus.Completed)
            session.Status = UploadSessionStatus.Aborted;
        await _db.SaveChangesAsync(cancellationToken);
        await _blobStorage.DeleteTempUploadAsync(session.Id, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return true;
    }
}
