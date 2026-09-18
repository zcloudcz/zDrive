using MediatR;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetShareByToken;

public sealed class GetShareByTokenQueryHandler : IRequestHandler<GetShareByTokenQuery, SharedFileDto>
{
    private readonly IFileDbContext _db;

    public GetShareByTokenQueryHandler(IFileDbContext db) => _db = db;

    public async Task<SharedFileDto> Handle(GetShareByTokenQuery request, CancellationToken cancellationToken)
    {
        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);
        return new SharedFileDto(share.ToDto().ToPublicDto(), share.File.ToDto().ToPublicDto());
    }
}
