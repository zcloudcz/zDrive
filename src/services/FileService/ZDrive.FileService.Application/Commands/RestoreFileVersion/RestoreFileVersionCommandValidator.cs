using FluentValidation;

namespace ZDrive.FileService.Application.Commands.RestoreFileVersion;

public sealed class RestoreFileVersionCommandValidator : AbstractValidator<RestoreFileVersionCommand>
{
    public RestoreFileVersionCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.VersionId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}
