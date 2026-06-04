using FluentValidation;

namespace ZDrive.SyncService.Application.Commands.ResolveConflict;

public sealed class ResolveConflictCommandValidator : AbstractValidator<ResolveConflictCommand>
{
    public ResolveConflictCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.ConflictId).NotEmpty();
        RuleFor(x => x.Resolution).IsInEnum();
    }
}
