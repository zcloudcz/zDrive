using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateShare;

namespace ZDrive.FileService.Tests.Unit;

// Regression: creating a share with an expiry answered 500 in production —
// the client sent "2026-09-27T00:00:00" (no offset), it deserialized as
// Kind=Unspecified and Npgsql refuses to write that into timestamptz.
[Trait("Category", "Unit")]
public sealed class CreateShareExpiryKindTests
{
    [Fact]
    public void ToUtc_UnspecifiedKind_IsTaggedUtcWithSameClockValue()
    {
        var input = new DateTime(2026, 9, 27, 0, 0, 0, DateTimeKind.Unspecified);

        var result = CreateShareCommandHandler.ToUtc(input);

        result!.Value.Kind.Should().Be(DateTimeKind.Utc);
        result.Value.Ticks.Should().Be(input.Ticks);
    }

    [Fact]
    public void ToUtc_LocalKind_IsConvertedToTheSameInstant()
    {
        var input = new DateTime(2026, 9, 27, 12, 0, 0, DateTimeKind.Local);

        var result = CreateShareCommandHandler.ToUtc(input);

        result!.Value.Kind.Should().Be(DateTimeKind.Utc);
        result.Value.Should().Be(input.ToUniversalTime());
    }

    [Fact]
    public void ToUtc_UtcAndNull_PassThrough()
    {
        var utc = new DateTime(2026, 9, 27, 0, 0, 0, DateTimeKind.Utc);

        CreateShareCommandHandler.ToUtc(utc).Should().Be(utc);
        CreateShareCommandHandler.ToUtc(null).Should().BeNull();
    }
}
