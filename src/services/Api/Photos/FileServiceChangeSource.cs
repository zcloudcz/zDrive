using MediatR;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Queries.GetFileChangeHead;
using ZDrive.FileService.Application.Queries.GetFileNodeBatch;
using ZDrive.FileService.Application.Queries.GetFileChangeBatch;
using ZDrive.PhotoService.Application.Interfaces.Ingest;

namespace ZDrive.Api.Photos;

/// <summary>
/// Photo → File boundary: the ingest worker reads FileService's global change
/// feed through its MediatR query, never through its DbContext.
/// </summary>
public sealed class FileServiceChangeSource : IFileChangeSource
{
    private readonly IMediator _mediator;

    public FileServiceChangeSource(IMediator mediator) => _mediator = mediator;

    public async Task<FileChangeBatch> ReadBatchAsync(long cursor, int limit, CancellationToken cancellationToken)
    {
        var page = await _mediator.Send(new GetFileChangeBatchQuery(cursor, limit), cancellationToken);

        return new FileChangeBatch(Map(page.Files), page.NextCursor, page.HasMore);
    }

    public Task<long> ReadSafeHeadAsync(CancellationToken cancellationToken) =>
        _mediator.Send(new GetFileChangeHeadQuery(), cancellationToken);

    public async Task<FileNodePage> ReadNodesAsync(Guid? afterId, int limit, CancellationToken cancellationToken)
    {
        var page = await _mediator.Send(new GetFileNodeBatchQuery(afterId, limit), cancellationToken);
        return new FileNodePage(Map(page.Files), page.LastId, page.HasMore);
    }

    private static List<ChangedFile> Map(IEnumerable<ChangedFileDto> files) => files
        .Select(f => new ChangedFile(
            f.FileId,
            f.TenantId,
            f.UserId,
            f.Node is null
                ? null
                : new FileSnapshot(f.Node.Name, f.Node.MimeType, f.Node.IsFolder, f.Node.IsDeleted, f.Node.ManifestHash, f.Node.CreatedAt)))
        .ToList();
}
