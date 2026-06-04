using MediatR;

namespace ZDrive.StorageService.Application.Commands.DeleteBlob;

public sealed record DeleteBlobCommand(Guid TenantId, Guid UserId, Guid FileId) : IRequest<bool>;
