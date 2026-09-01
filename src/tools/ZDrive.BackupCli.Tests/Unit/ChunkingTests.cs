using System.Security.Cryptography;
using FluentAssertions;
using ZDrive.BackupCli.Backup;

namespace ZDrive.BackupCli.Tests.Unit;

public sealed class ChunkingTests
{
    [Fact]
    public async Task ComputeChunksAsync_SmallFile_SingleChunkMatchingWholeFileHash()
    {
        var path = Path.GetTempFileName();
        try
        {
            var content = "hello zdrive"u8.ToArray();
            await File.WriteAllBytesAsync(path, content);

            var chunks = await Chunking.ComputeChunksAsync(path, CancellationToken.None);

            chunks.Should().ContainSingle();
            chunks[0].Index.Should().Be(0);
            chunks[0].Size.Should().Be(content.Length);
            chunks[0].Hash.Should().Be(Convert.ToHexString(SHA256.HashData(content)).ToLowerInvariant());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task ComputeChunksAsync_LargerThanChunkSize_SplitsIntoMultipleChunks()
    {
        var path = Path.GetTempFileName();
        try
        {
            var content = new byte[Chunking.ChunkSize + 1234];
            Random.Shared.NextBytes(content);
            await File.WriteAllBytesAsync(path, content);

            var chunks = await Chunking.ComputeChunksAsync(path, CancellationToken.None);

            chunks.Should().HaveCount(2);
            chunks[0].Size.Should().Be(Chunking.ChunkSize);
            chunks[1].Size.Should().Be(1234);
            chunks.Sum(c => c.Size).Should().Be(content.Length);
            chunks[0].Hash.Should().NotBe(chunks[1].Hash);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task ComputeChunksAsync_EmptyFile_ProducesOneZeroByteChunk()
    {
        var path = Path.GetTempFileName();
        try
        {
            var chunks = await Chunking.ComputeChunksAsync(path, CancellationToken.None);

            chunks.Should().ContainSingle();
            chunks[0].Size.Should().Be(0);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
