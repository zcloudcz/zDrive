using MediatR;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetStorageUsage;

public sealed class GetStorageUsageQueryHandler : IRequestHandler<GetStorageUsageQuery, StorageUsage>
{
    private readonly IStorageQuota _quota;

    public GetStorageUsageQueryHandler(IStorageQuota quota) => _quota = quota;

    public Task<StorageUsage> Handle(GetStorageUsageQuery request, CancellationToken cancellationToken) =>
        _quota.GetUsageAsync(request.TenantId, request.UserId, request.ClaimQuotaBytes, cancellationToken);
}
