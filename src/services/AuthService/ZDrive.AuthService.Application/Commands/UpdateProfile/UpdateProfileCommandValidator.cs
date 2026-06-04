using FluentValidation;

namespace ZDrive.AuthService.Application.Commands.UpdateProfile;

public sealed class UpdateProfileCommandValidator : AbstractValidator<UpdateProfileCommand>
{
    public UpdateProfileCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();

        RuleFor(x => x.DisplayName)
            .MaximumLength(200)
            .When(x => x.DisplayName is not null);

        RuleFor(x => x.AvatarUrl)
            .MaximumLength(2048)
            .Must(url => Uri.TryCreate(url, UriKind.Absolute, out _))
            .WithMessage("AvatarUrl must be a valid absolute URL.")
            .When(x => x.AvatarUrl is not null);
    }
}
