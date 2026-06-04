using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.CompleteUpload;

public sealed class CompleteUploadCommandValidator : AbstractValidator<CompleteUploadCommand>
{
    public CompleteUploadCommandValidator()
    {
        RuleFor(x => x.SessionId).NotEmpty();
    }
}
