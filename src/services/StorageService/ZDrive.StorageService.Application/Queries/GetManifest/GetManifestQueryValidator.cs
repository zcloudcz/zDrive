using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.GetManifest;

public sealed class GetManifestQueryValidator : AbstractValidator<GetManifestQuery>
{
    public GetManifestQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.ManifestHash)
            .Matches("\\A[a-f0-9]{64}\\z")
            .When(x => x.ManifestHash is not null)
            .WithMessage("ManifestHash must be a 64-character lowercase hex SHA-256.");
    }
}
