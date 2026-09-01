namespace ZDrive.BackupCli.Api;

/// <summary>
/// A request failed with a well-formed API error envelope (or a clearly
/// identifiable auth failure). The message is safe to print — it never
/// includes the password.
/// </summary>
public sealed class ZdriveApiException(string message) : Exception(message);
