using FluentValidation;

namespace ZDrive.FileService.Application.Queries.SearchFiles;

public sealed class SearchFilesQueryValidator : AbstractValidator<SearchFilesQuery>
{
    public SearchFilesQueryValidator()
    {
        RuleFor(x => x.Query).NotEmpty().MaximumLength(256);
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}
