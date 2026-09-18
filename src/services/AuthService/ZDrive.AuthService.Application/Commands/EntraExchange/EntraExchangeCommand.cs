using MediatR;
using ZDrive.AuthService.Application.DTOs;

namespace ZDrive.AuthService.Application.Commands.EntraExchange;

public sealed record EntraExchangeCommand(string AccessToken) : IRequest<AuthTokenDto>;
