using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Commands.DismissMemory;

public sealed class DismissMemoryCommandHandler : IRequestHandler<DismissMemoryCommand, bool>
{
    private readonly IPhotoDbContext _db;

    public DismissMemoryCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<bool> Handle(DismissMemoryCommand request, CancellationToken cancellationToken)
    {
        var memory = await _db.Memories
            .FirstOrDefaultAsync(m => m.Id == request.MemoryId && m.UserId == request.UserId, cancellationToken)
            ?? throw new NotFoundException("Memory", request.MemoryId);

        memory.Seen = true;
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }
}
