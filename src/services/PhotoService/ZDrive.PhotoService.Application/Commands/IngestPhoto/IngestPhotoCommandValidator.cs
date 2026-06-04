using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.IngestPhoto;

public sealed class IngestPhotoCommandValidator : AbstractValidator<IngestPhotoCommand>
{
    public IngestPhotoCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.OriginalFileName).NotEmpty().MaximumLength(1024);
        RuleFor(x => x.BlobPath).NotEmpty().MaximumLength(2048);
    }
}
