using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.ConfirmTwoFactor;

public sealed record ConfirmTwoFactorCommand(Guid UserId, string Code) : IRequest<RecoveryCodesDto>;
