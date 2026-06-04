using FluentValidation;

namespace ZDrive.PhotoService.Application.Queries.GetAlbumPhotos;

public sealed class GetAlbumPhotosQueryValidator : AbstractValidator<GetAlbumPhotosQuery>
{
    public GetAlbumPhotosQueryValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.AlbumId).NotEmpty();
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}
