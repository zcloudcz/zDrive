using FluentValidation;
using ZDrive.PhotoService.Application.Common;

namespace ZDrive.PhotoService.Application.Queries.GetPhotoThumbnail;

public sealed class GetPhotoThumbnailQueryValidator : AbstractValidator<GetPhotoThumbnailQuery>
{
    public GetPhotoThumbnailQueryValidator()
    {
        RuleFor(x => x.PhotoId).NotEmpty();
        RuleFor(x => x.Size)
            .Must(s => ThumbnailSizes.All.Contains(s))
            .WithMessage($"Size must be one of: {string.Join(", ", ThumbnailSizes.All)}.");
    }
}
