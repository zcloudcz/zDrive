using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.DeleteThumbnails;

public sealed class DeleteThumbnailsCommandValidator : AbstractValidator<DeleteThumbnailsCommand>
{
    public DeleteThumbnailsCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.PhotoId).NotEmpty();
    }
}
