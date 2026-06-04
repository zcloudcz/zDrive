using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.AddTag;

public sealed class AddTagCommandValidator : AbstractValidator<AddTagCommand>
{
    public AddTagCommandValidator()
    {
        RuleFor(x => x.PhotoId).NotEmpty();
        RuleFor(x => x.Tag).NotEmpty().MaximumLength(256);
        RuleFor(x => x.Confidence).InclusiveBetween(0f, 1f);
    }
}
