using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.GetChunkDownloadUrl;

public sealed class GetChunkDownloadUrlQueryValidator : AbstractValidator<GetChunkDownloadUrlQuery>
{
    public GetChunkDownloadUrlQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.ChunkHash).NotEmpty().MaximumLength(128);
    }
}
