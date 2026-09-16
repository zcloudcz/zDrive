using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Queries.GetManifest;

public sealed record GetManifestQuery(Guid TenantId, Guid UserId, Guid FileId, string? ManifestHash = null) : IRequest<ManifestDto>;
