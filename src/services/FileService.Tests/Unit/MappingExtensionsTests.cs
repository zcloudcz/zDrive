using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// FileDto.ToPublicDto(isShareRoot) is the one place that decides whether a
/// ParentId survives into an anonymous share-link response — every anonymous
/// handler that maps the shared ROOT must call it with isShareRoot: true.
/// </summary>
[Trait("Category", "Unit")]
public sealed class MappingExtensionsTests
{
    private static FileDto SampleDto(Guid? parentId) => new(
        Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), parentId, "name.txt", IsFolder: false,
        SizeBytes: 1, MimeType: null, BlobPath: "blob/path", ManifestHash: null,
        IsDeleted: false, DeletedAt: null, CreatedAt: DateTime.UtcNow, UpdatedAt: DateTime.UtcNow);

    [Fact]
    public void ToPublicDto_ShareRoot_BlanksParentId()
    {
        var dto = SampleDto(Guid.NewGuid());

        var result = dto.ToPublicDto(isShareRoot: true);

        result.ParentId.Should().BeNull();
    }

    [Fact]
    public void ToPublicDto_NotShareRoot_KeepsRealParentId()
    {
        var parentId = Guid.NewGuid();
        var dto = SampleDto(parentId);

        var result = dto.ToPublicDto();

        result.ParentId.Should().Be(parentId);
    }
}
