using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.SetupTwoFactor;

// Password: re-authentication, so a stolen access token alone cannot bind an
// attacker's authenticator to the account.
public sealed record SetupTwoFactorCommand(Guid UserId, string Password) : IRequest<TwoFactorSetupDto>;
