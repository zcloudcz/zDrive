using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Queries.GetFile;

public sealed class GetFileQueryHandler : IRequestHandler<GetFileQuery, FileDto>
{
    private readonly IFileDbContext _db;

    public GetFileQueryHandler(IFileDbContext db) => _db = db;

    public async Task<FileDto> Handle(GetFileQuery request, CancellationToken cancellationToken)
    {
        var node = await _db.FileNodes
            .AsNoTracking()
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && !f.IsDeleted,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        return node.ToDto();
    }
}
