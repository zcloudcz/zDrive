using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.SetupTwoFactor;

public sealed record SetupTwoFactorCommand(Guid UserId) : IRequest<TwoFactorSetupDto>;
