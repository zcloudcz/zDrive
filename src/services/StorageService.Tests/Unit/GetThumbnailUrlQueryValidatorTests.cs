using FluentValidation.TestHelper;
using Xunit;
using ZDrive.StorageService.Application.Queries.GetThumbnailUrl;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class GetThumbnailUrlQueryValidatorTests
{
    private readonly GetThumbnailUrlQueryValidator _validator = new();

    [Theory]
    [InlineData(256)]
    [InlineData(1024)]
    [InlineData(2048)]
    public void Valid_Size_Passes(int size)
    {
        var query = new GetThumbnailUrlQuery(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), size);
        var result = _validator.TestValidate(query);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(100)]
    [InlineData(512)]
    [InlineData(4096)]
    public void Invalid_Size_Fails(int size)
    {
        var query = new GetThumbnailUrlQuery(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), size);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.Size);
    }

    [Fact]
    public void Empty_PhotoId_Fails()
    {
        var query = new GetThumbnailUrlQuery(Guid.NewGuid(), Guid.NewGuid(), Guid.Empty, 256);
        var result = _validator.TestValidate(query);
        result.ShouldHaveValidationErrorFor(x => x.PhotoId);
    }
}
