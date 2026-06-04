using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.Register;

public sealed record RegisterCommand(
    string Email,
    string Password,
    string DisplayName) : IRequest<AuthTokenDto>;
