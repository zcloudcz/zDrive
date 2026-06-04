using ZDrive.SyncService.Domain.Entities;

namespace ZDrive.SyncService.Application.DTOs;

public static class MappingExtensions
{
    public static DeviceDto ToDto(this Device device) => new(
        device.Id,
        device.UserId,
        device.Name,
        device.Platform.ToString(),
        device.SyncCursor,
        device.LastSyncAt,
        device.CreatedAt);

    public static SyncEventDto ToDto(this SyncEvent syncEvent) => new(
        syncEvent.Id,
        syncEvent.UserId,
        syncEvent.DeviceId,
        syncEvent.FileId,
        syncEvent.EventType.ToString(),
        syncEvent.Metadata,
        syncEvent.CreatedAt);

    public static SyncConflictDto ToDto(this SyncConflict conflict) => new(
        conflict.Id,
        conflict.UserId,
        conflict.FileId,
        conflict.LocalDeviceId,
        conflict.RemoteDeviceId,
        conflict.LocalVersion,
        conflict.RemoteVersion,
        conflict.Status.ToString(),
        conflict.CreatedAt,
        conflict.ResolvedAt);
}
