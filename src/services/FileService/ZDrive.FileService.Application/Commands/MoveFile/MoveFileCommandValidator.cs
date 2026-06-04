using FluentValidation;

namespace ZDrive.FileService.Application.Commands.MoveFile;

public sealed class MoveFileCommandValidator : AbstractValidator<MoveFileCommand>
{
    public MoveFileCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
    }
}
