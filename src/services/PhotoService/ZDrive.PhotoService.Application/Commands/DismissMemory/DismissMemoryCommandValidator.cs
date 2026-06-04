using FluentValidation;

namespace ZDrive.PhotoService.Application.Commands.DismissMemory;

public sealed class DismissMemoryCommandValidator : AbstractValidator<DismissMemoryCommand>
{
    public DismissMemoryCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.MemoryId).NotEmpty();
    }
}
