using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.DownloadChunk;

public sealed class DownloadChunkQueryValidator : AbstractValidator<DownloadChunkQuery>
{
    public DownloadChunkQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
        RuleFor(x => x.ChunkHash).NotEmpty().MaximumLength(128);
    }
}
