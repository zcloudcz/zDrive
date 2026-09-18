using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Xunit;
using ZDrive.Shared.Http;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ShareResponseHeaderExtensionsTests
{
    [Fact]
    public void SetPublicShareCacheHeaders_SetsCacheControlAndVary()
    {
        var context = new DefaultHttpContext();

        context.Response.SetPublicShareCacheHeaders();

        context.Response.Headers.CacheControl.ToString().Should().Be("private, no-store");
        context.Response.Headers.Vary.ToString().Should().Be("X-Share-Grant");
    }
}
