using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;

public sealed record CreateShareDownloadGrantCommand(string LinkToken, Guid FileId) : IRequest<ShareDownloadGrantDto>;
