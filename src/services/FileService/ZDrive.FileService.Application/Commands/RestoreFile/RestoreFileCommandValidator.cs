using FluentValidation;

namespace ZDrive.FileService.Application.Commands.RestoreFile;

public sealed class RestoreFileCommandValidator : AbstractValidator<RestoreFileCommand>
{
    public RestoreFileCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
    }
}
