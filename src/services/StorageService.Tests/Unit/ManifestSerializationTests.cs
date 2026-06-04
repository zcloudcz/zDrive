using System.Text.Json;
using FluentAssertions;
using Xunit;
using ZDrive.StorageService.Domain.ValueObjects;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ManifestSerializationTests
{
    [Fact]
    public void ChunkManifest_RoundTrips_Correctly()
    {
        var fileId = Guid.NewGuid();
        var manifest = new ChunkManifest
        {
            FileId = fileId,
            TotalSize = 12345678,
            Chunks =
            [
                new ChunkInfo { Hash = "abc123", Index = 0, Size = 4000000 },
                new ChunkInfo { Hash = "def456", Index = 1, Size = 4000000 },
                new ChunkInfo { Hash = "ghi789", Index = 2, Size = 4345678 }
            ]
        };

        var json = JsonSerializer.Serialize(manifest);
        var deserialized = JsonSerializer.Deserialize<ChunkManifest>(json);

        deserialized.Should().NotBeNull();
        deserialized!.FileId.Should().Be(fileId);
        deserialized.TotalSize.Should().Be(12345678);
        deserialized.Chunks.Should().HaveCount(3);
        deserialized.Chunks[0].Hash.Should().Be("abc123");
        deserialized.Chunks[1].Index.Should().Be(1);
        deserialized.Chunks[2].Size.Should().Be(4345678);
    }

    [Fact]
    public void ChunkManifest_EmptyChunks_Serializes()
    {
        var manifest = new ChunkManifest
        {
            FileId = Guid.NewGuid(),
            TotalSize = 0,
            Chunks = []
        };

        var json = JsonSerializer.Serialize(manifest);
        var deserialized = JsonSerializer.Deserialize<ChunkManifest>(json);

        deserialized.Should().NotBeNull();
        deserialized!.Chunks.Should().BeEmpty();
        deserialized.TotalSize.Should().Be(0);
    }
}
