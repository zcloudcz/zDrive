namespace ZDrive.Shared.Exceptions;

public sealed class ForbiddenException : Exception
{
    public ForbiddenException(string? message = null)
        : base(message ?? "You do not have permission to perform this action.") { }
}
