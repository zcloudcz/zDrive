using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.CompleteUpload;

public sealed record CompleteUploadCommand(
    Guid SessionId,
    // Always the caller's own ids — see UploadChunkCommand's own note.
    Guid CallerTenantId,
    Guid CallerUserId,
    bool IsShared = false,
    Guid? ExpectedFileId = null) : IRequest<UploadCompleteDto>;
