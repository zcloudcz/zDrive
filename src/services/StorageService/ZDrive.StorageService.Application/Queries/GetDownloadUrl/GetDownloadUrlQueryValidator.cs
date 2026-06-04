using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.GetDownloadUrl;

public sealed class GetDownloadUrlQueryValidator : AbstractValidator<GetDownloadUrlQuery>
{
    public GetDownloadUrlQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
    }
}
