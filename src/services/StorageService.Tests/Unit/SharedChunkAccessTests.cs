using FluentAssertions;
using Xunit;
using ZDrive.StorageService.Application.Common;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class SharedChunkAccessTests
{
    [Fact]
    public void IsChunkInManifest_HashPresent_ReturnsTrue()
    {
        var manifest = new ManifestDto(100, [new ManifestChunkDto("aa", 0), new ManifestChunkDto("bb", 1)]);

        SharedChunkAccess.IsChunkInManifest(manifest, "bb").Should().BeTrue();
    }

    [Fact]
    public void IsChunkInManifest_HashFromADifferentVersion_ReturnsFalse()
    {
        var manifest = new ManifestDto(100, [new ManifestChunkDto("aa", 0)]);

        SharedChunkAccess.IsChunkInManifest(manifest, "cc").Should().BeFalse();
    }
}
