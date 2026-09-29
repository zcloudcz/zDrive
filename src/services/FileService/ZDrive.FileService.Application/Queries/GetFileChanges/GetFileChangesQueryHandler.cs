using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

public sealed class GetFileChangesQueryHandler : IRequestHandler<GetFileChangesQuery, FileChangesPageDto>
{
    private readonly IFileDbContext _db;

    public GetFileChangesQueryHandler(IFileDbContext db)
    {
        _db = db;
    }

    public async Task<FileChangesPageDto> Handle(GetFileChangesQuery request, CancellationToken cancellationToken)
    {
        var page = await FileChangeFeedReader.ReadAsync(
            _db,
            q => q.Where(c => c.TenantId == request.TenantId && c.UserId == request.UserId),
            request.Cursor,
            request.Limit,
            cancellationToken);

        // nextCursor advances to the last row of the prefix even though some
        // of those rows are about to be dropped below for being the caller's
        // own device. An excluded row still moved the cursor past it — so a
        // caller whose only remaining rows are its own writes doesn't
        // re-scan that same growing tail on every poll.
        //
        // In memory, after nextCursor is already fixed, so exclusion never
        // affects paging. A row with no origin (null) never equals a device
        // id, so it passes — only an exact device match is excluded.
        var visible = request.RequestingDeviceId.HasValue
            ? page.Prefix.Where(c => c.OriginDeviceId != request.RequestingDeviceId)
            : page.Prefix;

        var changes = visible.Select(c => c.ToDto()).ToList();

        return new FileChangesPageDto(changes, page.NextCursor, page.HasMore);
    }
}
