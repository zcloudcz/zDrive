namespace ZDrive.StorageService.Application.DTOs;

public sealed record UploadCompleteDto(string BlobPath, string ManifestHash, long TotalSize);
