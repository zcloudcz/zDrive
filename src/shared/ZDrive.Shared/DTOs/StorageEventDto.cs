namespace ZDrive.Shared.DTOs;

/// <summary>
/// Event DTO for Service Bus events emitted by the Storage Service.
/// </summary>
public sealed record StorageEventDto(
    Guid FileId,
    Guid TenantId,
    Guid UserId,
    string EventType,
    string? BlobPath,
    long? TotalSize);
