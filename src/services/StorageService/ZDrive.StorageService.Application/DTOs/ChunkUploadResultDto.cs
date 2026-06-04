namespace ZDrive.StorageService.Application.DTOs;

public sealed record ChunkUploadResultDto(Guid SessionId, int ChunkIndex, string ChunkHash, bool Accepted);
