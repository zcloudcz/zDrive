using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.RestoreManifest;

public sealed class RestoreManifestCommandValidator : AbstractValidator<RestoreManifestCommand>
{
    public RestoreManifestCommandValidator()
    {
        RuleFor(x => x.FileId).NotEmpty();

        // SHA-256 lowercase hex only. Strict format also prevents the hash from
        // smuggling path segments into the blob name (it is used in a blob path).
        RuleFor(x => x.ManifestHash)
            .NotEmpty()
            .Matches("^[a-f0-9]{64}$")
            .WithMessage("ManifestHash must be a 64-character lowercase hex SHA-256.");
    }
}
