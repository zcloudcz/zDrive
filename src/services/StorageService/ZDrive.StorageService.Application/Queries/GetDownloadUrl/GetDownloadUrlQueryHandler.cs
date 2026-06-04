using MediatR;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Queries.GetDownloadUrl;

public sealed class GetDownloadUrlQueryHandler : IRequestHandler<GetDownloadUrlQuery, DownloadUrlDto>
{
    private readonly IBlobStorageService _blobStorage;

    public GetDownloadUrlQueryHandler(IBlobStorageService blobStorage)
    {
        _blobStorage = blobStorage;
    }

    public Task<DownloadUrlDto> Handle(GetDownloadUrlQuery request, CancellationToken cancellationToken)
    {
        var sasUrl = _blobStorage.GenerateDownloadSasUrl(request.TenantId, request.UserId, request.FileId);
        var expiresAt = DateTime.UtcNow.AddHours(1);
        return Task.FromResult(new DownloadUrlDto(sasUrl, expiresAt));
    }
}
