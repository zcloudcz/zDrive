using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.InitUpload;

public sealed class InitUploadCommandValidator : AbstractValidator<InitUploadCommand>
{
    public InitUploadCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.FileName).NotEmpty().MaximumLength(1024);
        RuleFor(x => x.TotalChunks).GreaterThan(0).LessThanOrEqualTo(50_000);
    }
}
