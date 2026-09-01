namespace ZDrive.BackupCli.Api;

/// <summary>
/// Shared rule for when plain http:// is tolerated: only to localhost
/// (dev/test), or anywhere with an explicit ZDRIVE_ALLOW_INSECURE=1 opt-in.
/// Used both for the API base address (Program.cs, where the login body
/// carries the password) and for SAS URLs returned by the API (which grant
/// time-limited read access to file content).
/// </summary>
public static class InsecureHttpPolicy
{
    // Uri.IsLoopback is safe to use here: verified on .NET 8 that the Uri
    // parser itself canonicalizes aliases like "loopback" (and IP-literal
    // forms like "127.1" or "0x7f000001") into the real loopback host/IP at
    // parse time — Uri.Host already reflects the canonical value before any
    // check or DNS resolution happens. A genuinely different hostname (e.g.
    // "loopback.example.com") is correctly left as IsLoopback = false.
    public static bool IsBlocked(Uri uri) =>
        uri.Scheme == "http" && !uri.IsLoopback &&
        Environment.GetEnvironmentVariable("ZDRIVE_ALLOW_INSECURE") != "1";
}
