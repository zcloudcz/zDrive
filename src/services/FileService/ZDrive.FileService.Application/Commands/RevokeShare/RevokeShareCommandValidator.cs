using FluentValidation;

namespace ZDrive.FileService.Application.Commands.RevokeShare;

public sealed class RevokeShareCommandValidator : AbstractValidator<RevokeShareCommand>
{
    public RevokeShareCommandValidator()
    {
        RuleFor(x => x.ShareId).NotEmpty();
    }
}
