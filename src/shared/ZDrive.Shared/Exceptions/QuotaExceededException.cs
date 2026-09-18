namespace ZDrive.Shared.Exceptions;

public sealed class QuotaExceededException : Exception
{
    public QuotaExceededException(long limitBytes, long usedBytes)
        : base($"Storage quota exceeded: limit is {limitBytes} bytes, {usedBytes} bytes already used.")
    {
        LimitBytes = limitBytes;
        UsedBytes = usedBytes;
    }

    public long LimitBytes { get; }
    public long UsedBytes { get; }
}
