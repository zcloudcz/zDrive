using FluentValidation;

namespace ZDrive.AuthService.Application.Commands.LoginTwoFactor;

public sealed class LoginTwoFactorCommandValidator : AbstractValidator<LoginTwoFactorCommand>
{
    public LoginTwoFactorCommandValidator()
    {
        RuleFor(x => x.ChallengeToken).NotEmpty();
        RuleFor(x => x)
            .Must(x => string.IsNullOrWhiteSpace(x.Code) != string.IsNullOrWhiteSpace(x.RecoveryCode))
            .WithName("code")
            .WithMessage("Provide either code or recoveryCode.");
    }
}
