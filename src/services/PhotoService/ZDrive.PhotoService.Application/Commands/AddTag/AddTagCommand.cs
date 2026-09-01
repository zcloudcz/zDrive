using MediatR;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Application.Commands.AddTag;

public sealed record AddTagCommand(
    Guid UserId,
    Guid TenantId,
    Guid PhotoId,
    string Tag,
    float Confidence,
    TagSource Source) : IRequest<PhotoTagDto>;
