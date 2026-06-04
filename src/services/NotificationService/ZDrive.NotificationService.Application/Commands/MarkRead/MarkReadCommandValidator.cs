using FluentValidation;

namespace ZDrive.NotificationService.Application.Commands.MarkRead;

public sealed class MarkReadCommandValidator : AbstractValidator<MarkReadCommand>
{
    public MarkReadCommandValidator()
    {
        RuleFor(x => x.UserId)
            .NotEmpty();

        RuleFor(x => x.NotificationId)
            .NotEmpty();
    }
}
