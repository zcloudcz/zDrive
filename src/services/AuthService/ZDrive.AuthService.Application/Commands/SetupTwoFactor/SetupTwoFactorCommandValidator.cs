using FluentValidation;

namespace ZDrive.AuthService.Application.Commands.SetupTwoFactor;

public sealed class SetupTwoFactorCommandValidator : AbstractValidator<SetupTwoFactorCommand>
{
    public SetupTwoFactorCommandValidator()
    {
        RuleFor(x => x.Password).NotEmpty();
    }
}
