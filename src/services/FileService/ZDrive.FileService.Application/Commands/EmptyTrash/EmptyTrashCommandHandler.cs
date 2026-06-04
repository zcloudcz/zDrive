using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Commands.EmptyTrash;

public sealed class EmptyTrashCommandHandler : IRequestHandler<EmptyTrashCommand, int>
{
    private readonly IFileDbContext _db;

    public EmptyTrashCommandHandler(IFileDbContext db) => _db = db;

    public async Task<int> Handle(EmptyTrashCommand request, CancellationToken cancellationToken)
    {
        var trashedItems = await _db.FileNodes
            .Where(f =>
                f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && f.IsDeleted)
            .ToListAsync(cancellationToken);

        if (trashedItems.Count == 0)
            return 0;

        _db.FileNodes.RemoveRange(trashedItems);
        await _db.SaveChangesAsync(cancellationToken);

        return trashedItems.Count;
    }
}
