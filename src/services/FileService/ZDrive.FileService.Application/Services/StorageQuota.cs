using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Options;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Services;

public sealed class StorageQuota : IStorageQuota
{
    private readonly IFileDbContext _db;
    private readonly StorageOptions _options;

    public StorageQuota(IFileDbContext db, IOptions<StorageOptions> options)
    {
        _db = db;
        _options = options.Value;
    }

    // ponytail: SUM per write; keep a running counter if write throughput matters
    public async Task<StorageUsage> GetUsageAsync(Guid tenantId, Guid userId, long? claimLimit, CancellationToken ct)
    {
        var limit = claimLimit ?? _options.DefaultUserQuotaBytes;

        // Used bytes = every file_versions row belonging to the user's nodes,
        // including trashed nodes and superseded versions — that is what
        // actually sits in blob storage today (decided 18 Sep 2026).
        var used = await _db.FileVersions
            .Where(v => v.File.TenantId == tenantId && v.File.UserId == userId)
            .SumAsync(v => (long?)v.SizeBytes, ct) ?? 0;

        return new StorageUsage(limit, used);
    }

    public async Task EnsureCanStoreAsync(
        Guid tenantId, Guid userId, long? claimLimit, long additionalBytes, CancellationToken ct)
    {
        var usage = await GetUsageAsync(tenantId, userId, claimLimit, ct);
        if (usage.UsedBytes + additionalBytes > usage.LimitBytes)
            throw new QuotaExceededException(usage.LimitBytes, usage.UsedBytes);
    }
}
