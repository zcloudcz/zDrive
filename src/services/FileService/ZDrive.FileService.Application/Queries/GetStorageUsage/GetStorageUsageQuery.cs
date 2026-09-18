using MediatR;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetStorageUsage;

public sealed record GetStorageUsageQuery(Guid TenantId, Guid UserId, long? ClaimQuotaBytes) : IRequest<StorageUsage>;
