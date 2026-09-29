using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.PutThumbnail;

public sealed class PutThumbnailCommandValidator : AbstractValidator<PutThumbnailCommand>
{
    public PutThumbnailCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.PhotoId).NotEmpty();
        RuleFor(x => x.Size).GreaterThan(0);
        RuleFor(x => x.Content).NotEmpty();
    }
}
