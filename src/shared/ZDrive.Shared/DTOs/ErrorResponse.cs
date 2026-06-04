namespace ZDrive.Shared.DTOs;

/// <summary>
/// Standard error payload returned by all services.
/// </summary>
public sealed record ErrorResponse(string Code, string Message, IDictionary<string, string[]>? ValidationErrors = null);
