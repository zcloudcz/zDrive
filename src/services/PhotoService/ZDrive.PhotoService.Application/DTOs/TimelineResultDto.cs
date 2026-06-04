namespace ZDrive.PhotoService.Application.DTOs;

public sealed record TimelineResultDto(
    IReadOnlyList<PhotoDto> Photos,
    int TotalCount);
