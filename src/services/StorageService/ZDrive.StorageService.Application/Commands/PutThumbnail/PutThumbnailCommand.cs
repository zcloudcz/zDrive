using MediatR;

namespace ZDrive.StorageService.Application.Commands.PutThumbnail;

/// <summary>
/// Stores a generated thumbnail. Called in-process by the photo ingest worker;
/// there is deliberately no HTTP endpoint for it.
/// </summary>
public sealed record PutThumbnailCommand(Guid TenantId, Guid UserId, Guid PhotoId, int Size, byte[] Content) : IRequest<bool>;
