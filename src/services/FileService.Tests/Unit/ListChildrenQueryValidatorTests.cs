using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Queries.ListChildren;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ListChildrenQueryValidatorTests
{
    private readonly ListChildrenQueryValidator _validator = new();

    [Fact]
    public void Valid_Query_Passes()
    {
        var query = new ListChildrenQuery(Guid.NewGuid(), Guid.NewGuid(), null, 1, 50);
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Page_Zero_Fails()
    {
        var query = new ListChildrenQuery(Guid.NewGuid(), Guid.NewGuid(), null, 0, 50);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Page);
    }

    [Fact]
    public void PageSize_Zero_Fails()
    {
        var query = new ListChildrenQuery(Guid.NewGuid(), Guid.NewGuid(), null, 1, 0);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.PageSize);
    }

    [Fact]
    public void PageSize_TooLarge_Fails()
    {
        var query = new ListChildrenQuery(Guid.NewGuid(), Guid.NewGuid(), null, 1, 201);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.PageSize);
    }
}
