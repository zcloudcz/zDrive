using FluentValidation;

namespace ZDrive.PhotoService.Application.Queries.SearchPhotos;

public sealed class SearchPhotosQueryValidator : AbstractValidator<SearchPhotosQuery>
{
    public SearchPhotosQueryValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.Query).NotEmpty().MaximumLength(256);
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}
