using MediatR;
using ZDrive.FileService.Application.Commands.DeleteFile;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.DeleteSharedItem;

/// <summary>
/// DELETE /shares/link/{token}/items/{id} — soft-deletes an item inside the
/// share on behalf of the owner, through the same command the authenticated
/// trash flow uses. The shared root itself is never deletable through its
/// own link (there would be nothing left to browse) — 403, same as any other
/// permission failure, not 404 (the id plainly exists, it's the root).
/// </summary>
public sealed class DeleteSharedItemCommandHandler : IRequestHandler<DeleteSharedItemCommand, bool>
{
    private readonly IFileDbContext _db;
    private readonly IMediator _mediator;

    public DeleteSharedItemCommandHandler(IFileDbContext db, IMediator mediator)
    {
        _db = db;
        _mediator = mediator;
    }

    public async Task<bool> Handle(DeleteSharedItemCommand request, CancellationToken cancellationToken)
    {
        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);
        PublicShareAccess.RequireDelete(share);

        var item = await PublicShareAccess.FindWithinShareAsync(_db, share, request.ItemId, cancellationToken);
        if (item is null)
            throw new NotFoundException("FileNode", request.ItemId);

        if (item.Id == share.FileId)
            throw new ForbiddenException("The shared item itself cannot be deleted through its own link.");

        var owner = share.File;
        return await _mediator.Send(new DeleteFileCommand(owner.UserId, owner.TenantId, item.Id), cancellationToken);
    }
}
