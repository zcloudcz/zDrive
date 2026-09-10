using MediatR;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.StorageService.Application.Queries.GetManifest;

public sealed class GetManifestQueryHandler : IRequestHandler<GetManifestQuery, ManifestDto>
{
    private readonly IBlobStorageService _blobStorage;

    public GetManifestQueryHandler(IBlobStorageService blobStorage)
    {
        _blobStorage = blobStorage;
    }

    public async Task<ManifestDto> Handle(GetManifestQuery request, CancellationToken cancellationToken)
    {
        var manifest = await _blobStorage.DownloadManifestAsync(
            request.TenantId, request.UserId, request.FileId, cancellationToken)
            ?? throw new NotFoundException("Manifest", request.FileId);

        return new ManifestDto(
            manifest.TotalSize,
            manifest.Chunks.Select(c => new ManifestChunkDto(c.Hash, c.Index)).ToList());
    }
}
