using MediatR;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.StorageService.Application.Queries.DownloadChunk;

public sealed class DownloadChunkQueryHandler : IRequestHandler<DownloadChunkQuery, Stream>
{
    private readonly IBlobStorageService _blobStorage;

    public DownloadChunkQueryHandler(IBlobStorageService blobStorage)
    {
        _blobStorage = blobStorage;
    }

    public async Task<Stream> Handle(DownloadChunkQuery request, CancellationToken cancellationToken)
    {
        var stream = await _blobStorage.DownloadChunkAsync(
            request.TenantId, request.UserId, request.FileId, request.ChunkHash, cancellationToken);

        return stream ?? throw new NotFoundException("Chunk", request.ChunkHash);
    }
}
