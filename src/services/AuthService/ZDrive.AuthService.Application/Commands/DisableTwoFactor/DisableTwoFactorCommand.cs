using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.DisableTwoFactor;

// Code is a current TOTP code, or an unused recovery code for a user who
// lost their authenticator. Returns a fresh token pair: every other session
// is signed out.
public sealed record DisableTwoFactorCommand(Guid UserId, string Password, string Code) : IRequest<AuthTokenDto>;
