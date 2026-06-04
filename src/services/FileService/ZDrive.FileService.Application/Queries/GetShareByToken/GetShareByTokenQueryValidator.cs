using FluentValidation;

namespace ZDrive.FileService.Application.Queries.GetShareByToken;

public sealed class GetShareByTokenQueryValidator : AbstractValidator<GetShareByTokenQuery>
{
    public GetShareByTokenQueryValidator()
    {
        RuleFor(x => x.LinkToken).NotEmpty();
    }
}
