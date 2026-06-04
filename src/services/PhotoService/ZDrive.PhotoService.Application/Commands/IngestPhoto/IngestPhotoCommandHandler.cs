using System.Globalization;
using System.Text.RegularExpressions;
using MediatR;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Application.Commands.IngestPhoto;

public sealed partial class IngestPhotoCommandHandler : IRequestHandler<IngestPhotoCommand, PhotoDto>
{
    private readonly IPhotoDbContext _db;

    public IngestPhotoCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<PhotoDto> Handle(IngestPhotoCommand request, CancellationToken cancellationToken)
    {
        var photo = new Photo
        {
            Id = Guid.NewGuid(),
            FileId = request.FileId,
            UserId = request.UserId,
            TenantId = request.TenantId,
            OriginalFileName = request.OriginalFileName,
            BlobPath = request.BlobPath,
            TakenAt = TryParseDateFromFileName(request.OriginalFileName),
            ProcessingStatus = ProcessingStatus.Ingested,
        };

        _db.Photos.Add(photo);
        await _db.SaveChangesAsync(cancellationToken);

        return photo.ToDto();
    }

    /// <summary>
    /// Attempts to extract a date/time from the file name when no EXIF data is available.
    /// Supports patterns like: IMG_20231225_143022, 2023-12-25_14-30-22, 20231225_143022.
    /// </summary>
    internal static DateTime? TryParseDateFromFileName(string fileName)
    {
        var name = Path.GetFileNameWithoutExtension(fileName);

        // Pattern: 20231225_143022 or IMG_20231225_143022
        var match = DateTimePattern().Match(name);
        if (match.Success)
        {
            var dateStr = $"{match.Groups[1].Value}-{match.Groups[2].Value}-{match.Groups[3].Value} " +
                          $"{match.Groups[4].Value}:{match.Groups[5].Value}:{match.Groups[6].Value}";

            if (DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dt))
                return DateTime.SpecifyKind(dt, DateTimeKind.Utc);
        }

        // Pattern: 2023-12-25_14-30-22 or 2023-12-25 14-30-22
        var dashMatch = DashDateTimePattern().Match(name);
        if (dashMatch.Success)
        {
            var dateStr = $"{dashMatch.Groups[1].Value}-{dashMatch.Groups[2].Value}-{dashMatch.Groups[3].Value} " +
                          $"{dashMatch.Groups[4].Value}:{dashMatch.Groups[5].Value}:{dashMatch.Groups[6].Value}";

            if (DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dt))
                return DateTime.SpecifyKind(dt, DateTimeKind.Utc);
        }

        return null;
    }

    // 20231225_143022 — optionally preceded by prefix like IMG_
    [GeneratedRegex(@"(\d{4})(\d{2})(\d{2})[_\-](\d{2})(\d{2})(\d{2})")]
    private static partial Regex DateTimePattern();

    // 2023-12-25_14-30-22
    [GeneratedRegex(@"(\d{4})-(\d{2})-(\d{2})[_ ](\d{2})-(\d{2})-(\d{2})")]
    private static partial Regex DashDateTimePattern();
}
