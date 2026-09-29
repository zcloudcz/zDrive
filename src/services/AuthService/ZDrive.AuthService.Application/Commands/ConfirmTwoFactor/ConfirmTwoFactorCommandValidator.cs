using FluentValidation;

namespace ZDrive.AuthService.Application.Commands.ConfirmTwoFactor;

public sealed class ConfirmTwoFactorCommandValidator : AbstractValidator<ConfirmTwoFactorCommand>
{
    public ConfirmTwoFactorCommandValidator()
    {
        RuleFor(x => x.Code).NotEmpty().Matches(@"^\d{6}$").WithMessage("Code must be 6 digits.");
    }
}
