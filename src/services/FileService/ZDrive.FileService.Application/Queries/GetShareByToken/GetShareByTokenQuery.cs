using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetShareByToken;

public sealed record GetShareByTokenQuery(string LinkToken) : IRequest<SharedFileDto>;
