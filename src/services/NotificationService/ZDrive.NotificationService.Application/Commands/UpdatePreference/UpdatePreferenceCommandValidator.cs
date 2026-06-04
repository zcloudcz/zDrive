using FluentValidation;

namespace ZDrive.NotificationService.Application.Commands.UpdatePreference;

public sealed class UpdatePreferenceCommandValidator : AbstractValidator<UpdatePreferenceCommand>
{
    public UpdatePreferenceCommandValidator()
    {
        RuleFor(x => x.UserId)
            .NotEmpty();

        RuleFor(x => x.Channel)
            .IsInEnum();

        RuleFor(x => x.Type)
            .IsInEnum();
    }
}
