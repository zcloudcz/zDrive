using FluentValidation;

namespace ZDrive.NotificationService.Application.Commands.SendNotification;

public sealed class SendNotificationCommandValidator : AbstractValidator<SendNotificationCommand>
{
    public SendNotificationCommandValidator()
    {
        RuleFor(x => x.UserId)
            .NotEmpty();

        RuleFor(x => x.Type)
            .IsInEnum();

        RuleFor(x => x.Title)
            .NotEmpty()
            .MaximumLength(500);

        RuleFor(x => x.Body)
            .NotEmpty()
            .MaximumLength(4000);

        RuleFor(x => x.Data)
            .MaximumLength(8000)
            .When(x => x.Data is not null);
    }
}
