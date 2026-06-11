using MediatR;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Commands.RestoreManifest;

public sealed class RestoreManifestCommandHandler : IRequestHandler<RestoreManifestCommand, bool>
{
    private readonly IBlobStorageService _blobStorage;

    public RestoreManifestCommandHandler(IBlobStorageService blobStorage) => _blobStorage = blobStorage;

    public async Task<bool> Handle(RestoreManifestCommand request, CancellationToken cancellationToken)
    {
        var restored = await _blobStorage.RestoreManifestSnapshotAsync(
            request.TenantId, request.UserId, request.FileId, request.ManifestHash, cancellationToken);

        if (!restored)
            throw new NotFoundException("ManifestSnapshot", request.ManifestHash);

        return true;
    }
}
