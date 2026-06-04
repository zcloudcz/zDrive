using FluentValidation;

namespace ZDrive.FileService.Application.Queries.ListChildren;

public sealed class ListChildrenQueryValidator : AbstractValidator<ListChildrenQuery>
{
    public ListChildrenQueryValidator()
    {
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}
