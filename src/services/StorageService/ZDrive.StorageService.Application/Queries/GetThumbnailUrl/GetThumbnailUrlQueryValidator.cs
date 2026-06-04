using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.GetThumbnailUrl;

public sealed class GetThumbnailUrlQueryValidator : AbstractValidator<GetThumbnailUrlQuery>
{
    private static readonly int[] AllowedSizes = [256, 1024, 2048];

    public GetThumbnailUrlQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.PhotoId).NotEmpty();
        RuleFor(x => x.Size)
            .Must(s => AllowedSizes.Contains(s))
            .WithMessage($"Size must be one of: {string.Join(", ", AllowedSizes)}.");
    }
}
