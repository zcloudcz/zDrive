using MediatR;

namespace ZDrive.StorageService.Application.Commands.DeleteThumbnails;

/// <summary>Removes every thumbnail of one photo (all versions and sizes). In-process only.</summary>
public sealed record DeleteThumbnailsCommand(Guid TenantId, Guid UserId, Guid PhotoId) : IRequest<bool>;
