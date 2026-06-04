using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Queries.SearchFiles;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class SearchFilesQueryValidatorTests
{
    private readonly SearchFilesQueryValidator _validator = new();

    [Fact]
    public void Valid_Query_Passes()
    {
        var query = new SearchFilesQuery(Guid.NewGuid(), Guid.NewGuid(), "documents");
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_Query_Fails()
    {
        var query = new SearchFilesQuery(Guid.NewGuid(), Guid.NewGuid(), "");
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Query);
    }

    [Fact]
    public void Query_Too_Long_Fails()
    {
        var query = new SearchFilesQuery(Guid.NewGuid(), Guid.NewGuid(), new string('a', 257));
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Query);
    }

    [Fact]
    public void Page_Zero_Fails()
    {
        var query = new SearchFilesQuery(Guid.NewGuid(), Guid.NewGuid(), "test", Page: 0);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Page);
    }

    [Fact]
    public void PageSize_TooLarge_Fails()
    {
        var query = new SearchFilesQuery(Guid.NewGuid(), Guid.NewGuid(), "test", PageSize: 201);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.PageSize);
    }
}
