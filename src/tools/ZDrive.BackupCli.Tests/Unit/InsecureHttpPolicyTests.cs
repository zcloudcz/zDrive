using FluentAssertions;
using ZDrive.BackupCli.Api;

namespace ZDrive.BackupCli.Tests.Unit;

/// <summary>
/// Env-var mutation makes this test collection non-parallel-safe against
/// itself; xunit already serializes tests within one class by default.
/// </summary>
public sealed class InsecureHttpPolicyTests : IDisposable
{
    private readonly string? _previous = Environment.GetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE");

    public void Dispose() => Environment.SetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE", _previous);

    [Theory]
    [InlineData("http://localhost:5000/")]
    [InlineData("http://127.0.0.1:5000/")]
    [InlineData("http://[::1]:5000/")]
    [InlineData("https://backup.example.com/")]
    public void IsBlocked_LocalhostOrHttps_ReturnsFalse(string url)
    {
        Environment.SetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE", null);

        InsecureHttpPolicy.IsBlocked(new Uri(url)).Should().BeFalse();
    }

    [Fact]
    public void IsBlocked_BareLoopbackAlias_ReturnsFalse()
    {
        Environment.SetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE", null);

        // "loopback" is a hardcoded alias the Uri parser itself rewrites to
        // "localhost" at construction time (verified against .NET 8) — it is
        // not a DNS-resolvable hostname that could be rebound to a remote
        // host, so it's correctly treated the same as "localhost" here.
        InsecureHttpPolicy.IsBlocked(new Uri("http://loopback/")).Should().BeFalse();
    }

    [Fact]
    public void IsBlocked_LoopbackLikeButDifferentDomain_ReturnsTrue()
    {
        Environment.SetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE", null);

        // Unlike the bare "loopback" alias above, this is a genuinely
        // different, DNS-resolvable hostname and must not be trusted.
        InsecureHttpPolicy.IsBlocked(new Uri("http://loopback.example.com/")).Should().BeTrue();
    }

    [Fact]
    public void IsBlocked_RemoteHttpWithoutOptIn_ReturnsTrue()
    {
        Environment.SetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE", null);

        InsecureHttpPolicy.IsBlocked(new Uri("http://backup.example.com/")).Should().BeTrue();
    }

    [Fact]
    public void IsBlocked_RemoteHttpWithOptIn_ReturnsFalse()
    {
        Environment.SetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE", "1");

        InsecureHttpPolicy.IsBlocked(new Uri("http://backup.example.com/")).Should().BeFalse();
    }
}
