using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;

namespace ZDrive.FileService.Infrastructure.Persistence.Interceptors;

/// <summary>
/// Appends FileChange rows for every FileNode mutation, inside the same
/// SaveChanges call that makes the mutation itself — one transaction, no
/// dual write, no outbox. This is what makes the change feed authoritative
/// for every client that goes through FileService (desktop, web, mobile,
/// BackupCli), regardless of which command handler wrote the change.
/// </summary>
public sealed class FileChangeInterceptor : SaveChangesInterceptor
{
    private readonly IChangeOrigin _changeOrigin;
    private readonly TimeProvider _timeProvider;

    public FileChangeInterceptor(IChangeOrigin changeOrigin, TimeProvider timeProvider)
    {
        _changeOrigin = changeOrigin;
        _timeProvider = timeProvider;
    }

    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData, InterceptionResult<int> result)
    {
        RecordChanges(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        RecordChanges(eventData.Context);
        return ValueTask.FromResult(result);
    }

    private void RecordChanges(DbContext? context)
    {
        if (context is null)
            return;

        var originDeviceId = _changeOrigin.DeviceId;
        var occurredAt = _timeProvider.GetUtcNow().UtcDateTime;

        foreach (var entry in context.ChangeTracker.Entries<FileNode>())
        {
            var node = entry.Entity;

            switch (entry.State)
            {
                case EntityState.Added:
                    AddChange(context, node, FileChangeType.Create, originDeviceId, occurredAt);
                    break;

                case EntityState.Modified:
                    var isDeleted = entry.Property(f => f.IsDeleted);
                    if (isDeleted.IsModified)
                    {
                        // Soft delete / restore is reported as exactly one
                        // change. E.g. a restore that also clears ParentId
                        // (parent was gone too) is still just a Create — the
                        // restore already tells the other side everything it
                        // needs, a Move on top would be redundant noise.
                        var becameDeleted = (bool)isDeleted.CurrentValue!;
                        AddChange(context, node, becameDeleted ? FileChangeType.Delete : FileChangeType.Create, originDeviceId, occurredAt);
                        break;
                    }

                    if (entry.Property(f => f.ParentId).IsModified)
                        AddChange(context, node, FileChangeType.Move, originDeviceId, occurredAt);

                    if (entry.Property(f => f.Name).IsModified)
                        AddChange(context, node, FileChangeType.Rename, originDeviceId, occurredAt);

                    if (entry.Property(f => f.ManifestHash).IsModified || entry.Property(f => f.SizeBytes).IsModified)
                        AddChange(context, node, FileChangeType.Update, originDeviceId, occurredAt);
                    break;

                case EntityState.Deleted:
                    // Hard delete (EmptyTrash): the item was already reported
                    // as Delete when it was soft-deleted into trash.
                    break;
            }
        }
    }

    private static void AddChange(
        DbContext context, FileNode node, FileChangeType type, Guid? originDeviceId, DateTime occurredAt)
    {
        context.Set<FileChange>().Add(new FileChange
        {
            TenantId = node.TenantId,
            UserId = node.UserId,
            FileId = node.Id,
            Type = type,
            OriginDeviceId = originDeviceId,
            OccurredAt = occurredAt
        });
    }
}
