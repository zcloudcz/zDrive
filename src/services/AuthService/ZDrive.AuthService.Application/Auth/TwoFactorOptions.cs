namespace ZDrive.AuthService.Application.Auth;

public sealed class TwoFactorOptions
{
    public const string SectionName = "TwoFactor";

    // Per user, across all challenges and the disable endpoint: at most this
    // many second-factor attempts per window, then further attempts are
    // refused with the ordinary invalid-code response until the window ends.
    public int MaxFailedAttempts { get; set; } = 10;
    public int FailureWindowMinutes { get; set; } = 15;
}
