using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetShareInfo;

public sealed record GetShareInfoQuery(string LinkToken) : IRequest<ShareInfoDto>;
