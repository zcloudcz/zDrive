using MediatR;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Queries.GetChunkDownloadUrl;

public sealed class GetChunkDownloadUrlQueryHandler : IRequestHandler<GetChunkDownloadUrlQuery, DownloadUrlDto>
{
    private readonly IBlobStorageService _blobStorage;

    public GetChunkDownloadUrlQueryHandler(IBlobStorageService blobStorage)
    {
        _blobStorage = blobStorage;
    }

    public Task<DownloadUrlDto> Handle(GetChunkDownloadUrlQuery request, CancellationToken cancellationToken)
    {
        var sasUrl = _blobStorage.GenerateChunkDownloadSasUrl(
            request.TenantId, request.UserId, request.FileId, request.ChunkHash);
        var expiresAt = DateTime.UtcNow.AddHours(1);
        return Task.FromResult(new DownloadUrlDto(sasUrl, expiresAt));
    }
}
