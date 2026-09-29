using MediatR;

namespace ZDrive.AuthService.Application.Commands.DisableTwoFactor;

// Code is a current TOTP code, or an unused recovery code for a user who
// lost their authenticator.
public sealed record DisableTwoFactorCommand(Guid UserId, string Password, string Code) : IRequest;
