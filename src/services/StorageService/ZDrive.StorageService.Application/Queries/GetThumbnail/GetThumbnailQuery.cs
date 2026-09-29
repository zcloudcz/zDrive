using MediatR;

namespace ZDrive.StorageService.Application.Queries.GetThumbnail;

public sealed record GetThumbnailQuery(Guid TenantId, Guid UserId, Guid PhotoId, int Size) : IRequest<Stream>;
