using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.RevokeShare;

public sealed class RevokeShareCommandHandler : IRequestHandler<RevokeShareCommand, bool>
{
    private readonly IFileDbContext _db;

    public RevokeShareCommandHandler(IFileDbContext db) => _db = db;

    public async Task<bool> Handle(RevokeShareCommand request, CancellationToken cancellationToken)
    {
        var share = await _db.Shares
            .FirstOrDefaultAsync(s =>
                s.Id == request.ShareId
                && s.SharedBy == request.UserId,
                cancellationToken)
            ?? throw new NotFoundException("Share", request.ShareId);

        _db.Shares.Remove(share);
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }
}
