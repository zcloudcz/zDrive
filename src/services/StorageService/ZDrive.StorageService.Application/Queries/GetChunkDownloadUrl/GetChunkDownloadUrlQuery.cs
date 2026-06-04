using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Queries.GetChunkDownloadUrl;

public sealed record GetChunkDownloadUrlQuery(Guid TenantId, Guid UserId, Guid FileId, string ChunkHash) : IRequest<DownloadUrlDto>;
