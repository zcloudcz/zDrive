using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Queries.GetDownloadUrl;

public sealed record GetDownloadUrlQuery(Guid TenantId, Guid UserId, Guid FileId) : IRequest<DownloadUrlDto>;
