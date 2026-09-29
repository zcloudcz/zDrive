using FluentValidation;

namespace ZDrive.FileService.Application.Queries.GetFileChangeBatch;

public sealed class GetFileChangeBatchQueryValidator : AbstractValidator<GetFileChangeBatchQuery>
{
    public GetFileChangeBatchQueryValidator()
    {
        RuleFor(x => x.Cursor).GreaterThanOrEqualTo(0);
        RuleFor(x => x.Limit).InclusiveBetween(1, 1000);
    }
}
