using MediatR;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Queries.GetFileChanges;

namespace ZDrive.FileService.Application.Queries.GetFileChangeHead;

public sealed class GetFileChangeHeadQueryHandler : IRequestHandler<GetFileChangeHeadQuery, long>
{
    private readonly IFileDbContext _db;

    public GetFileChangeHeadQueryHandler(IFileDbContext db) => _db = db;

    public Task<long> Handle(GetFileChangeHeadQuery request, CancellationToken cancellationToken) =>
        FileChangeFeedReader.ReadSafeHeadAsync(_db, cancellationToken);
}
