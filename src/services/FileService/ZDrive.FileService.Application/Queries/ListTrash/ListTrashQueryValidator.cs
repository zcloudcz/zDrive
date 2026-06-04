using FluentValidation;

namespace ZDrive.FileService.Application.Queries.ListTrash;

public sealed class ListTrashQueryValidator : AbstractValidator<ListTrashQuery>
{
    public ListTrashQueryValidator()
    {
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}
