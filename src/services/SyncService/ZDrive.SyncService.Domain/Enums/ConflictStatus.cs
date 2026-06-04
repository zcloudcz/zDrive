namespace ZDrive.SyncService.Domain.Enums;

public enum ConflictStatus
{
    Pending = 0,
    ResolvedLocal = 1,
    ResolvedRemote = 2,
    ResolvedMerge = 3
}
