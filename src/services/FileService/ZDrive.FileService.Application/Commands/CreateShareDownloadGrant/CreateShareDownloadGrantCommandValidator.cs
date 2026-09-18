using FluentValidation;

namespace ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;

public sealed class CreateShareDownloadGrantCommandValidator : AbstractValidator<CreateShareDownloadGrantCommand>
{
    public CreateShareDownloadGrantCommandValidator()
    {
        RuleFor(x => x.LinkToken).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
    }
}
