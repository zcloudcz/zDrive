using System.Net;
using System.Text.Json;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using ZDrive.FileService.Infrastructure.Persistence.Configurations;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Api.Middleware;

/// <summary>
/// Global exception handler that converts domain exceptions to appropriate HTTP responses.
/// </summary>
public sealed class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        var (statusCode, error) = exception switch
        {
            ValidationException validationEx => (
                HttpStatusCode.BadRequest,
                new ErrorResponse(
                    "VALIDATION_ERROR",
                    "One or more validation errors occurred.",
                    validationEx.Errors
                        .GroupBy(e => e.PropertyName)
                        .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray()))),

            NotFoundException notFoundEx => (
                HttpStatusCode.NotFound,
                new ErrorResponse("NOT_FOUND", notFoundEx.Message)),

            ConflictException conflictEx => (
                HttpStatusCode.Conflict,
                new ErrorResponse("CONFLICT", conflictEx.Message)),

            ForbiddenException forbiddenEx => (
                HttpStatusCode.Forbidden,
                new ErrorResponse("FORBIDDEN", forbiddenEx.Message)),

            QuotaExceededException quotaEx => (
                HttpStatusCode.RequestEntityTooLarge,
                new ErrorResponse("QUOTA_EXCEEDED", quotaEx.Message)),

            TooManyRequestsException tooManyEx => (
                HttpStatusCode.TooManyRequests,
                new ErrorResponse("TOO_MANY_PENDING_UPLOADS", tooManyEx.Message)),

            // The per-handler `AnyAsync` sibling-name pre-check is only a fast
            // path, not the real guard — the unique index on
            // (tenant_id, user_id, parent_id, name_normalized) WHERE is_deleted
            // = false is. It can fire past the pre-check: restore has no
            // pre-check at all, two concurrent requests can both pass it before
            // either inserts, and .NET's ToLowerInvariant and Postgres's
            // lower() do not fold every character identically. A unique
            // violation here is a naming conflict the caller can react to, not
            // a server bug — map it to 409 instead of letting it fall through
            // to the 500 default below. Matched on the index name, not on
            // 23505 alone: file_versions has its own unique index
            // (file_id, version_number), and a violation there is not a
            // naming conflict, so this message would be wrong for it.
            DbUpdateException
            {
                InnerException: PostgresException
                {
                    SqlState: PostgresErrorCodes.UniqueViolation,
                    ConstraintName: FileNodeConfiguration.NameUniqueIndexName
                }
            } => (
                HttpStatusCode.Conflict,
                new ErrorResponse("CONFLICT", "A file or folder with that name already exists in this location.")),

            _ => (
                HttpStatusCode.InternalServerError,
                new ErrorResponse("INTERNAL_ERROR", "An unexpected error occurred."))
        };

        if (statusCode == HttpStatusCode.InternalServerError)
            _logger.LogError(exception, "Unhandled exception");
        else
            _logger.LogWarning(exception, "Handled exception: {StatusCode}", statusCode);

        context.Response.ContentType = "application/json";
        context.Response.StatusCode = (int)statusCode;

        var response = ApiResponse<object>.Fail(error.Code, error.Message);
        var payload = error.ValidationErrors is not null
            ? new { response.Success, response.Data, Error = error }
            : (object)response;

        await context.Response.WriteAsync(JsonSerializer.Serialize(payload, JsonOptions));
    }
}
