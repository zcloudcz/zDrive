using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;

namespace ZDrive.PhotoService.Application.Queries.GetMemories;

public sealed class GetMemoriesQueryHandler : IRequestHandler<GetMemoriesQuery, List<MemoryDto>>
{
    private readonly IPhotoDbContext _db;

    public GetMemoriesQueryHandler(IPhotoDbContext db) => _db = db;

    public async Task<List<MemoryDto>> Handle(GetMemoriesQuery request, CancellationToken cancellationToken)
    {
        return await _db.Memories.AsNoTracking()
            .Where(m => m.UserId == request.UserId && !m.Seen)
            .OrderByDescending(m => m.GeneratedAt)
            .Select(m => m.ToDto())
            .ToListAsync(cancellationToken);
    }
}
