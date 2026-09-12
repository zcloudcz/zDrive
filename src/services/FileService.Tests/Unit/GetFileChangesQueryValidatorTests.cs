using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Queries.GetFileChanges;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class GetFileChangesQueryValidatorTests
{
    private readonly GetFileChangesQueryValidator _validator = new();

    [Fact]
    public void Valid_Query_Passes()
    {
        var query = new GetFileChangesQuery(Guid.NewGuid(), Guid.NewGuid(), 0, 500);
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Cursor_Negative_Fails()
    {
        var query = new GetFileChangesQuery(Guid.NewGuid(), Guid.NewGuid(), -1, 500);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Cursor);
    }

    [Fact]
    public void Cursor_Zero_Passes()
    {
        var query = new GetFileChangesQuery(Guid.NewGuid(), Guid.NewGuid(), 0, 500);
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveValidationErrorFor(x => x.Cursor);
    }

    [Fact]
    public void Limit_Zero_Fails()
    {
        var query = new GetFileChangesQuery(Guid.NewGuid(), Guid.NewGuid(), 0, 0);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Limit);
    }

    [Fact]
    public void Limit_TooLarge_Fails()
    {
        var query = new GetFileChangesQuery(Guid.NewGuid(), Guid.NewGuid(), 0, 1001);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Limit);
    }

    [Fact]
    public void Limit_AtMax_Passes()
    {
        var query = new GetFileChangesQuery(Guid.NewGuid(), Guid.NewGuid(), 0, 1000);
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveValidationErrorFor(x => x.Limit);
    }
}
