namespace ZDrive.FileService.Application.Interfaces;

/// <summary>Interface names and shape are binding — package A (share-link write API) compiles against them.</summary>
public interface IStorageQuota
{
    Task<StorageUsage> GetUsageAsync(Guid tenantId, Guid userId, long? claimLimit, CancellationToken ct);

    /// <summary>Throws <see cref="ZDrive.Shared.Exceptions.QuotaExceededException"/> when
    /// <paramref name="additionalBytes"/> would push usage past the limit.</summary>
    Task EnsureCanStoreAsync(Guid tenantId, Guid userId, long? claimLimit, long additionalBytes, CancellationToken ct);
}

public sealed record StorageUsage(long LimitBytes, long UsedBytes);
