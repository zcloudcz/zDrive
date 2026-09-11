using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.RenameFile;

public sealed class RenameFileCommandHandler : IRequestHandler<RenameFileCommand, FileDto>
{
    private readonly IFileDbContext _db;

    public RenameFileCommandHandler(IFileDbContext db) => _db = db;

    public async Task<FileDto> Handle(RenameFileCommand request, CancellationToken cancellationToken)
    {
        var node = await _db.FileNodes
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && !f.IsDeleted,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        // Prevent duplicate names in the same folder. Case-insensitive —
        // see CreateFileCommandHandler for why.
        var duplicate = await _db.FileNodes.AnyAsync(f =>
            f.TenantId == request.TenantId
            && f.UserId == request.UserId
            && f.ParentId == node.ParentId
            && f.Name.ToLower() == request.NewName.ToLowerInvariant()
            && f.Id != node.Id
            && !f.IsDeleted,
            cancellationToken);

        if (duplicate)
            throw new ConflictException($"A file or folder named '{request.NewName}' already exists in this location.");

        node.Name = request.NewName;
        node.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        return node.ToDto();
    }
}
