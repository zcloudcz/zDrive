using FluentValidation;

namespace ZDrive.FileService.Application.Commands.CreateShare;

public sealed class CreateShareCommandValidator : AbstractValidator<CreateShareCommand>
{
    public CreateShareCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.Permission).IsInEnum();
        RuleFor(x => x.ExpiresAt)
            .GreaterThan(DateTime.UtcNow)
            .When(x => x.ExpiresAt.HasValue)
            .WithMessage("ExpiresAt must be in the future.");
    }
}
