using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.InitUpload;

public sealed record InitUploadCommand(
    Guid UserId,
    Guid TenantId,
    Guid FileId,
    string FileName,
    int TotalChunks) : IRequest<UploadSessionDto>;
