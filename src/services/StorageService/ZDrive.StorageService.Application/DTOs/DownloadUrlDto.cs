namespace ZDrive.StorageService.Application.DTOs;

public sealed record DownloadUrlDto(string SasUrl, DateTime ExpiresAt);
