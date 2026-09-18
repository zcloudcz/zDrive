using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Queries.ListSharedChildren;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ListSharedChildrenQueryValidatorTests
{
    private readonly ListSharedChildrenQueryValidator _validator = new();

    [Fact]
    public void Valid_Query_Passes()
    {
        var result = _validator.TestValidate(new ListSharedChildrenQuery("token123", null));
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void EmptyLinkToken_Fails()
    {
        var result = _validator.TestValidate(new ListSharedChildrenQuery("", null));
        result.ShouldHaveValidationErrorFor(x => x.LinkToken);
    }
}
