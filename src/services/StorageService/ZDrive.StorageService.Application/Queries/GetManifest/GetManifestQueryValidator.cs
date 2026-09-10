using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.GetManifest;

public sealed class GetManifestQueryValidator : AbstractValidator<GetManifestQuery>
{
    public GetManifestQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
    }
}
