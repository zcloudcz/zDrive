using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Queries.GetFileVersions;

public sealed class GetFileVersionsQueryHandler : IRequestHandler<GetFileVersionsQuery, List<FileVersionDto>>
{
    private readonly IFileDbContext _db;

    public GetFileVersionsQueryHandler(IFileDbContext db) => _db = db;

    public async Task<List<FileVersionDto>> Handle(GetFileVersionsQuery request, CancellationToken cancellationToken)
    {
        // Verify the file exists and belongs to the user.
        var fileExists = await _db.FileNodes.AnyAsync(f =>
            f.Id == request.FileId
            && f.TenantId == request.TenantId
            && f.UserId == request.UserId
            && !f.IsDeleted,
            cancellationToken);

        if (!fileExists)
            throw new NotFoundException("FileNode", request.FileId);

        var versions = await _db.FileVersions
            .AsNoTracking()
            .Where(v => v.FileId == request.FileId)
            .OrderByDescending(v => v.VersionNumber)
            .ToListAsync(cancellationToken);

        return versions.Select(v => v.ToDto()).ToList();
    }
}
