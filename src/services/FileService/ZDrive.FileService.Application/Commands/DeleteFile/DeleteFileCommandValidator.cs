using FluentValidation;

namespace ZDrive.FileService.Application.Commands.DeleteFile;

public sealed class DeleteFileCommandValidator : AbstractValidator<DeleteFileCommand>
{
    public DeleteFileCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
    }
}
