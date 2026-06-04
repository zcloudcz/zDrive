using FluentValidation;

namespace ZDrive.SyncService.Application.Queries.PullChanges;

public sealed class PullChangesQueryValidator : AbstractValidator<PullChangesQuery>
{
    public PullChangesQueryValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.DeviceId).NotEmpty();
        RuleFor(x => x.Cursor).GreaterThanOrEqualTo(0);
    }
}
