using MediatR;
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

        var files = page.Files
            .Select(f => new ChangedFile(
                f.FileId,
                f.TenantId,
                f.UserId,
                f.Node is null
                    ? null
                    : new FileSnapshot(f.Node.Name, f.Node.MimeType, f.Node.IsFolder, f.Node.IsDeleted, f.Node.ManifestHash, f.Node.CreatedAt)))
            .ToList();

        return new FileChangeBatch(files, page.NextCursor, page.HasMore);
    }
}
