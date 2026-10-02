using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.LoginTwoFactor;

// Exactly one of Code (TOTP) and RecoveryCode.
public sealed record LoginTwoFactorCommand(
    string ChallengeToken,
    string? Code,
    string? RecoveryCode) : IRequest<AuthTokenDto>;
