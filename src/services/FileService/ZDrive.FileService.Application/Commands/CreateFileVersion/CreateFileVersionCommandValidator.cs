using FluentValidation;

namespace ZDrive.FileService.Application.Commands.CreateFileVersion;

public sealed class CreateFileVersionCommandValidator : AbstractValidator<CreateFileVersionCommand>
{
    public CreateFileVersionCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.BlobVersionId).NotEmpty().MaximumLength(512);
        RuleFor(x => x.SizeBytes).GreaterThanOrEqualTo(0);
        RuleFor(x => x.CreatedBy).NotEmpty();
        RuleFor(x => x.Comment).MaximumLength(1024).When(x => x.Comment is not null);
    }
}
