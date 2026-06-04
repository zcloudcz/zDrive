using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Queries.GetShareByToken;

public sealed class GetShareByTokenQueryHandler : IRequestHandler<GetShareByTokenQuery, SharedFileDto>
{
    private readonly IFileDbContext _db;

    public GetShareByTokenQueryHandler(IFileDbContext db) => _db = db;

    public async Task<SharedFileDto> Handle(GetShareByTokenQuery request, CancellationToken cancellationToken)
    {
        var share = await _db.Shares
            .AsNoTracking()
            .Include(s => s.File)
            .FirstOrDefaultAsync(s => s.LinkToken == request.LinkToken, cancellationToken)
            ?? throw new NotFoundException("Share", request.LinkToken);

        if (share.IsExpired)
            throw new NotFoundException("Share", request.LinkToken);

        if (share.File.IsDeleted)
            throw new NotFoundException("FileNode", share.FileId);

        return new SharedFileDto(share.ToDto(), share.File.ToDto());
    }
}
