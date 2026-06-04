using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.DeleteAlbum;

public sealed class DeleteAlbumCommandValidator : AbstractValidator<DeleteAlbumCommand>
{
    public DeleteAlbumCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.AlbumId).NotEmpty();
    }
}
