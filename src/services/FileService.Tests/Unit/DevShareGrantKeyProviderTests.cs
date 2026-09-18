using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// No other test in this repo sets ZDRIVE_DEV_KEY_DIR, so running these
/// sequentially (not in parallel with each other) via a dedicated temp dir
/// per test is enough to avoid collisions — each test restores the
/// environment variable in a finally block regardless of outcome.
/// </summary>
[Trait("Category", "Unit")]
public sealed class DevShareGrantKeyProviderTests
{
    [Fact]
    public void GetOrCreateKey_NoExistingFile_CreatesAndReturnsAValidKey()
    {
        using var tempDir = new TempDevKeyDir();

        var key = DevShareGrantKeyProvider.GetOrCreateKey();

        File.Exists(Path.Combine(tempDir.Path, "share-grant.key")).Should().BeTrue();
        var options = new ShareDownloadGrantOptions { DownloadGrantKey = key };
        options.TryGetKey(out _).Should().BeTrue("the generated key must be at least 32 bytes of valid base64");
    }

    [Fact]
    public void GetOrCreateKey_CalledTwice_ReturnsTheSameBytesBothTimes()
    {
        using var tempDir = new TempDevKeyDir();

        var first = DevShareGrantKeyProvider.GetOrCreateKey();
        var second = DevShareGrantKeyProvider.GetOrCreateKey();

        second.Should().Be(first);
    }

    [Fact]
    public void GetOrCreateKey_RespectsKeyDirEnvVarOverride()
    {
        using var tempDir = new TempDevKeyDir();

        DevShareGrantKeyProvider.GetOrCreateKey();

        Directory.GetFiles(tempDir.Path, "share-grant.key").Should().ContainSingle(
            "the override directory, not the default ~/.zdrive/dev-keys, must receive the file");
    }

    /// <summary>
    /// Points DevJwtKeyProvider.KeyDirEnvVar (shared by DevShareGrantKeyProvider)
    /// at a fresh temp directory for the lifetime of one test, then cleans up.
    /// </summary>
    private sealed class TempDevKeyDir : IDisposable
    {
        private readonly string? _previousValue;

        public string Path { get; } = Directory.CreateTempSubdirectory("zdrive-share-grant-key-test-").FullName;

        public TempDevKeyDir()
        {
            _previousValue = Environment.GetEnvironmentVariable(DevJwtKeyProvider.KeyDirEnvVar);
            Environment.SetEnvironmentVariable(DevJwtKeyProvider.KeyDirEnvVar, Path);
        }

        public void Dispose()
        {
            Environment.SetEnvironmentVariable(DevJwtKeyProvider.KeyDirEnvVar, _previousValue);
            Directory.Delete(Path, recursive: true);
        }
    }
}
