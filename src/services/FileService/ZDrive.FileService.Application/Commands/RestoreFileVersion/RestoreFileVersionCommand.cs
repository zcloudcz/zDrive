using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.RestoreFileVersion;

/// <summary>
/// Restores an older version of a file: file metadata (size, manifest hash)
/// is rolled back and the restore is recorded as a NEW version, so history
/// stays linear and the restore itself is undoable.
///
/// The blob-side manifest flip is a separate StorageService call
/// (POST /storage/files/{fileId}/manifests/{hash}/restore) — the client
/// orchestrates both, consistent with the upload flow.
/// </summary>
public sealed record RestoreFileVersionCommand(
    Guid TenantId,
    Guid UserId,
    Guid FileId,
    Guid VersionId) : IRequest<FileVersionDto>;
