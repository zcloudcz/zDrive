using FluentValidation;

namespace ZDrive.NotificationService.Application.Commands.BroadcastFileChange;

public sealed class BroadcastFileChangeCommandValidator : AbstractValidator<BroadcastFileChangeCommand>
{
    public BroadcastFileChangeCommandValidator()
    {
        RuleFor(x => x.UserId)
            .NotEmpty();

        RuleFor(x => x.FileId)
            .NotEmpty();

        RuleFor(x => x.ChangeType)
            .NotEmpty()
            .MaximumLength(50);

        RuleFor(x => x.FileName)
            .NotEmpty()
            .MaximumLength(500);
    }
}
