using MediatR;
using ZDrive.FileService.Application.Commands.CreateFile;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateSharedFolder;

/// <summary>
/// POST /shares/link/{token}/folders — creates a folder under the shared
/// root (or a descendant of it) on behalf of the share OWNER. Reuses
/// CreateFileCommand rather than inserting a FileNode directly, so name
/// collision / parent validation stays in exactly one place for both the
/// authenticated and the link-driven flow.
/// </summary>
public sealed class CreateSharedFolderCommandHandler : IRequestHandler<CreateSharedFolderCommand, FileDto>
{
    private readonly IFileDbContext _db;
    private readonly IMediator _mediator;

    public CreateSharedFolderCommandHandler(IFileDbContext db, IMediator mediator)
    {
        _db = db;
        _mediator = mediator;
    }

    public async Task<FileDto> Handle(CreateSharedFolderCommand request, CancellationToken cancellationToken)
    {
        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);
        PublicShareAccess.RequireWrite(share);

        var parentId = request.ParentId ?? share.FileId;
        var parent = await PublicShareAccess.FindWithinShareAsync(_db, share, parentId, cancellationToken);
        if (parent is null || !parent.IsFolder)
            throw new NotFoundException("Folder", parentId);

        var owner = share.File;
        var command = new CreateFileCommand(
            owner.UserId, owner.TenantId, parent.Id, request.Name, IsFolder: true,
            SizeBytes: null, MimeType: null, BlobPath: null, ManifestHash: null);

        var created = await _mediator.Send(command, cancellationToken);
        return created.ToPublicDto();
    }
}
