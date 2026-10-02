using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.Login;

public sealed record LoginCommand(
    string Email,
    string Password) : IRequest<LoginResultDto>;
