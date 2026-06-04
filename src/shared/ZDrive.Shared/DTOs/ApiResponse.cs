namespace ZDrive.Shared.DTOs;

/// <summary>
/// Standard API response wrapper.
/// </summary>
public sealed class ApiResponse<T>
{
    public bool Success { get; init; }
    public T? Data { get; init; }
    public ErrorResponse? Error { get; init; }

    public static ApiResponse<T> Ok(T data) => new() { Success = true, Data = data };
    public static ApiResponse<T> Fail(string code, string message) =>
        new() { Success = false, Error = new ErrorResponse(code, message) };
}
