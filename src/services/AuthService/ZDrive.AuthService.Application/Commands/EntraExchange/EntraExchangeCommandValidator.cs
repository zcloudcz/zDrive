using FluentValidation;

namespace ZDrive.AuthService.Application.Commands.EntraExchange;

public sealed class EntraExchangeCommandValidator : AbstractValidator<EntraExchangeCommand>
{
    public EntraExchangeCommandValidator()
    {
        RuleFor(x => x.AccessToken).NotEmpty();
    }
}
