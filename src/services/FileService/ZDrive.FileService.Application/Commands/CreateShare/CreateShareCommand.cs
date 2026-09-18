using MediatR;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Domain.Enums;

namespace ZDrive.FileService.Application.Commands.CreateShare;

public sealed record CreateShareCommand(
    Guid UserId,
    Guid FileId,
    Guid? SharedWith,
    Permission Permission,
    string? Password,
    DateTime? ExpiresAt,
    bool AllowDelete = false) : IRequest<ShareDto>;
