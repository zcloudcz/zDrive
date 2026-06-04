using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.UpdateAlbum;

public sealed class UpdateAlbumCommandValidator : AbstractValidator<UpdateAlbumCommand>
{
    public UpdateAlbumCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.AlbumId).NotEmpty();
        RuleFor(x => x.Name).MaximumLength(256).When(x => x.Name is not null);
    }
}
