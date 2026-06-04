namespace ZDrive.StorageService.Application.DTOs;

public sealed record UploadSessionDto(Guid SessionId, string SasUploadUrl);
