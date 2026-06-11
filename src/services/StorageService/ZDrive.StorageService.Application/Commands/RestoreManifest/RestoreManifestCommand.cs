using MediatR;

namespace ZDrive.StorageService.Application.Commands.RestoreManifest;

/// <summary>
/// Makes an older manifest snapshot the current manifest of a file,
/// effectively restoring that file version in blob storage. The caller
/// (client, after FileService confirmed the version) supplies the manifest
/// hash recorded for the version being restored.
/// </summary>
public sealed record RestoreManifestCommand(
    Guid TenantId,
    Guid UserId,
    Guid FileId,
    string ManifestHash) : IRequest<bool>;
