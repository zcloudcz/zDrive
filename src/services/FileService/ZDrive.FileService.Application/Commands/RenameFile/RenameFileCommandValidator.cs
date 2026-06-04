using FluentValidation;

namespace ZDrive.FileService.Application.Commands.RenameFile;

public sealed class RenameFileCommandValidator : AbstractValidator<RenameFileCommand>
{
    public RenameFileCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.NewName).NotEmpty().MaximumLength(512);
    }
}
