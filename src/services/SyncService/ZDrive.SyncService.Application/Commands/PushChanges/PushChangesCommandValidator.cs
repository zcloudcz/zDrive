using FluentValidation;

namespace ZDrive.SyncService.Application.Commands.PushChanges;

public sealed class PushChangesCommandValidator : AbstractValidator<PushChangesCommand>
{
    public PushChangesCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.DeviceId).NotEmpty();
        RuleFor(x => x.Events).NotNull();
        RuleFor(x => x.BaseCursor).GreaterThanOrEqualTo(0).When(x => x.BaseCursor.HasValue);
        RuleForEach(x => x.Events).ChildRules(e =>
        {
            e.RuleFor(x => x.FileId).NotEmpty();
            e.RuleFor(x => x.EventType).IsInEnum();
        });
    }
}
