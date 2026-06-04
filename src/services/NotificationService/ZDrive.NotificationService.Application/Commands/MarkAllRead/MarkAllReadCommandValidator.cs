using FluentValidation;

namespace ZDrive.NotificationService.Application.Commands.MarkAllRead;

public sealed class MarkAllReadCommandValidator : AbstractValidator<MarkAllReadCommand>
{
    public MarkAllReadCommandValidator()
    {
        RuleFor(x => x.UserId)
            .NotEmpty();
    }
}
