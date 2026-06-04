namespace ZDrive.FileService.Application.DTOs;

public sealed record SharedFileDto(
    ShareDto Share,
    FileDto File);
