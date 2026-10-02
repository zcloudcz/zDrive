namespace ZDrive.AuthService.Application.Interfaces;

/// <summary>TOTP per RFC 6238: SHA-1, 6 digits, 30 s step, ±1 step tolerance.</summary>
public interface ITotpService
{
    /// <summary>New random secret, Base32-encoded.</summary>
    string GenerateSecret();

    string BuildOtpAuthUri(string secret, string accountName);

    /// <summary>
    /// True when <paramref name="code"/> is valid within the tolerance window
    /// and its time step is later than <paramref name="lastUsedStep"/>.
    /// </summary>
    bool TryVerify(string secret, string code, long? lastUsedStep, out long timeStep);
}
