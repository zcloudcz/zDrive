using MediatR;

namespace ZDrive.StorageService.Application.Queries.GetThumbnailUrl;

public sealed record GetThumbnailUrlQuery(Guid TenantId, Guid UserId, Guid PhotoId, int Size) : IRequest<string>;
