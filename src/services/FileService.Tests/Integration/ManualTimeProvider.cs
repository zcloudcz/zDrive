namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Controllable clock for testing the change feed's 5-second commit-order
/// hold-back (see GetFileChangesQueryHandler): tests need to record a change
/// "now" and then prove it stays hidden until the clock has moved forward.
/// </summary>
public sealed class ManualTimeProvider : TimeProvider
{
    private DateTimeOffset _now = DateTimeOffset.UtcNow;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan by) => _now += by;
}
