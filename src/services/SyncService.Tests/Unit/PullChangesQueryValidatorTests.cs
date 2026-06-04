using FluentValidation.TestHelper;
using Xunit;
using ZDrive.SyncService.Application.Queries.PullChanges;

namespace ZDrive.SyncService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class PullChangesQueryValidatorTests
{
    private readonly PullChangesQueryValidator _validator = new();

    [Theory]
    [InlineData(0)]
    [InlineData(100)]
    [InlineData(999999)]
    public void Valid_Query_Passes(long cursor)
    {
        var query = new PullChangesQuery(Guid.NewGuid(), Guid.NewGuid(), cursor);
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var query = new PullChangesQuery(Guid.Empty, Guid.NewGuid(), 0);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_DeviceId_Fails()
    {
        var query = new PullChangesQuery(Guid.NewGuid(), Guid.Empty, 0);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.DeviceId);
    }

    [Fact]
    public void Negative_Cursor_Fails()
    {
        var query = new PullChangesQuery(Guid.NewGuid(), Guid.NewGuid(), -1);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Cursor);
    }
}
