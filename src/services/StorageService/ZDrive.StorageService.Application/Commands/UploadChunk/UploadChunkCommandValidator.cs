using FluentValidation;

namespace ZDrive.StorageService.Application.Commands.UploadChunk;

public sealed class UploadChunkCommandValidator : AbstractValidator<UploadChunkCommand>
{
    public UploadChunkCommandValidator()
    {
        RuleFor(x => x.SessionId).NotEmpty();
        RuleFor(x => x.ChunkIndex).GreaterThanOrEqualTo(0);
        RuleFor(x => x.ChunkHash).NotEmpty().MaximumLength(128);
        RuleFor(x => x.Stream).NotNull();
    }
}
