using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.DeleteBlob;

public sealed class DeleteBlobCommandValidator : AbstractValidator<DeleteBlobCommand>
{
    public DeleteBlobCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
    }
}
