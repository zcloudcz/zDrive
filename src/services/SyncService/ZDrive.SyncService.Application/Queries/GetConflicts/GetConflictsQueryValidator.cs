using FluentValidation;

namespace ZDrive.SyncService.Application.Queries.GetConflicts;

public sealed class GetConflictsQueryValidator : AbstractValidator<GetConflictsQuery>
{
    public GetConflictsQueryValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
    }
}
