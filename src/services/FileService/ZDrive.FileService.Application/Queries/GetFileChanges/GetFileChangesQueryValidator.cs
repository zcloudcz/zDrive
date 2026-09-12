using FluentValidation;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

public sealed class GetFileChangesQueryValidator : AbstractValidator<GetFileChangesQuery>
{
    public GetFileChangesQueryValidator()
    {
        RuleFor(x => x.Cursor).GreaterThanOrEqualTo(0);
        RuleFor(x => x.Limit).InclusiveBetween(1, 1000);
    }
}
