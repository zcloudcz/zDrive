using FluentValidation;

namespace ZDrive.FileService.Application.Queries.ListSharedChildren;

public sealed class ListSharedChildrenQueryValidator : AbstractValidator<ListSharedChildrenQuery>
{
    public ListSharedChildrenQueryValidator()
    {
        RuleFor(x => x.LinkToken).NotEmpty();
    }
}
