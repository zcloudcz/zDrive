using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Queries.GetPhoto;

public sealed record GetPhotoQuery(
    Guid UserId,
    Guid TenantId,
    Guid PhotoId) : IRequest<PhotoDto>;
