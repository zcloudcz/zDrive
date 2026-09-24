using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using FluentAssertions;
using Xunit;
using ZDrive.Api.Middleware;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Captures the formatted message of every log call, so tests can assert
/// on it without pulling in a mocking library just for ILogger.
/// </summary>
internal sealed class RecordingLogger<T> : ILogger<T>
{
    public List<string> Messages { get; } = new();

    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        Messages.Add(formatter(state, exception));
    }
}

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

    [Fact]
    public async Task InvokeAsync_ConflictException_LogsRequestMethodAndPath()
    {
        // A raw status code (e.g. 409) is not enough to trace which endpoint
        // raised it -- the log line must carry the request that failed.
        var logger = new RecordingLogger<ExceptionHandlingMiddleware>();
        var middleware = new ExceptionHandlingMiddleware(
            _ => throw new ConflictException("A user with email 'a@b.com' already exists."),
            logger);

        var context = new DefaultHttpContext();
        context.Request.Method = "POST";
        context.Request.Path = "/api/v1/auth/register";
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        logger.Messages.Should().ContainSingle(m =>
            m.Contains("POST") && m.Contains("/api/v1/auth/register"));
    }
}
