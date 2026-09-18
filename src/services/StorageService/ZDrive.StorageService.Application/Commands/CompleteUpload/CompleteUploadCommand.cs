using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.CompleteUpload;

public sealed record CompleteUploadCommand(
    Guid SessionId,
    Guid? ExpectedTenantId = null,
    Guid? ExpectedUserId = null,
    Guid? ExpectedFileId = null) : IRequest<UploadCompleteDto>;
