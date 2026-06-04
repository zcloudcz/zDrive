using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Commands.IngestPhoto;

public sealed record IngestPhotoCommand(
    Guid FileId,
    Guid UserId,
    Guid TenantId,
    string OriginalFileName,
    string BlobPath) : IRequest<PhotoDto>;
