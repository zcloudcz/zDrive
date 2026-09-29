namespace ZDrive.AuthService.Domain.Entities;

/// <summary>
/// Per-user second-factor bookkeeping that changes concurrently (replay
/// protection and the rolling failure cap). Kept off <see cref="User"/> so
/// concurrency checks on it can never turn an unrelated user update into an
/// error.
/// </summary>
public sealed class TwoFactorGuard
{
    public Guid UserId { get; set; }

    // RFC 6238 time step of the last accepted code — a code is only accepted
    // for a strictly later step, so the same code can't be replayed.
    public long? LastUsedStep { get; set; }

    // Second-factor attempts (login and disable) in the current window.
    public DateTime FailureWindowStart { get; set; }
    public int FailureCount { get; set; }

    // Concurrency token, replaced on every change.
    public Guid Version { get; set; } = Guid.NewGuid();

    public User User { get; set; } = null!;
}
