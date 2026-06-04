using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.AddPhotosToAlbum;

public sealed class AddPhotosToAlbumCommandValidator : AbstractValidator<AddPhotosToAlbumCommand>
{
    public AddPhotosToAlbumCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.AlbumId).NotEmpty();
        RuleFor(x => x.PhotoIds).NotEmpty();
        RuleForEach(x => x.PhotoIds).NotEmpty();
    }
}
