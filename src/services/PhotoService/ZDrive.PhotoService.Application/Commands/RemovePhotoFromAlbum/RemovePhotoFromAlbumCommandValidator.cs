using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.RemovePhotoFromAlbum;

public sealed class RemovePhotoFromAlbumCommandValidator : AbstractValidator<RemovePhotoFromAlbumCommand>
{
    public RemovePhotoFromAlbumCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.AlbumId).NotEmpty();
        RuleFor(x => x.PhotoId).NotEmpty();
    }
}
