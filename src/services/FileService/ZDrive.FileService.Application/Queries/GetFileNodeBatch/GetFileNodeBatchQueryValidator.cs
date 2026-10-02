using FluentValidation;

namespace ZDrive.FileService.Application.Queries.GetFileNodeBatch;

public sealed class GetFileNodeBatchQueryValidator : AbstractValidator<GetFileNodeBatchQuery>
{
    public GetFileNodeBatchQueryValidator() => RuleFor(x => x.Limit).InclusiveBetween(1, 1000);
}
