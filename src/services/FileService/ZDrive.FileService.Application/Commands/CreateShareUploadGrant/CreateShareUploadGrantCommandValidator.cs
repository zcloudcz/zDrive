using FluentValidation;

namespace ZDrive.FileService.Application.Commands.CreateShareUploadGrant;

public sealed class CreateShareUploadGrantCommandValidator : AbstractValidator<CreateShareUploadGrantCommand>
{
    public CreateShareUploadGrantCommandValidator()
    {
        RuleFor(x => x.LinkToken).NotEmpty();
        RuleFor(x => x.SizeBytes).GreaterThan(0);
    }
}
