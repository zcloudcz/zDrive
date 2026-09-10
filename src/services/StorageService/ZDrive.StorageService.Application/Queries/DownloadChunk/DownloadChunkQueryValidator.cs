using FluentValidation;

namespace ZDrive.StorageService.Application.Queries.DownloadChunk;

public sealed class DownloadChunkQueryValidator : AbstractValidator<DownloadChunkQuery>
{
    public DownloadChunkQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FileId).NotEmpty();
        // Chunks are addressed by their lowercase hex SHA-256, and the value
        // is interpolated into a blob path — constrain it to that shape
        // rather than to a length.
        RuleFor(x => x.ChunkHash).Matches("^[0-9a-f]{64}$");
    }
}
