using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Api.Middleware;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>413 / QUOTA_EXCEEDED mapping for QuotaExceededException (Package B contract).</summary>
[Trait("Category", "Unit")]
public sealed class ExceptionHandlingMiddlewareQuotaTests
{
    [Fact]
    public async Task InvokeAsync_QuotaExceededException_Returns413WithQuotaExceededCode()
    {
        var middleware = new ExceptionHandlingMiddleware(
            _ => throw new QuotaExceededException(limitBytes: 100, usedBytes: 100),
            NullLogger<ExceptionHandlingMiddleware>.Instance);

        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be((int)HttpStatusCode.RequestEntityTooLarge);

        context.Response.Body.Seek(0, SeekOrigin.Begin);
        var body = await new StreamReader(context.Response.Body).ReadToEndAsync();
        var response = JsonSerializer.Deserialize<ApiResponse<object>>(
            body, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase })!;

        response.Success.Should().BeFalse();
        response.Error!.Code.Should().Be("QUOTA_EXCEEDED");
        response.Error!.Message.Should().Contain("100");
    }
}
