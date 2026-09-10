using MediatR;

namespace ZDrive.StorageService.Application.Queries.DownloadChunk;

public sealed record DownloadChunkQuery(Guid TenantId, Guid UserId, Guid FileId, string ChunkHash) : IRequest<Stream>;
