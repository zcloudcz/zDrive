using OtpNet;
using ZDrive.AuthService.Application.Interfaces;

namespace ZDrive.AuthService.Infrastructure.Auth;

public sealed class TotpService : ITotpService
{
    private const string Issuer = "zDrive";
    private const int SecretBytes = 20; // 160 bits, the RFC 4226 recommendation for SHA-1

    // ±1 step of 30 s tolerates clock drift between server and phone.
    private static readonly VerificationWindow Window = new(previous: 1, future: 1);

    public string GenerateSecret() =>
        Base32Encoding.ToString(KeyGeneration.GenerateRandomKey(SecretBytes));

    public string BuildOtpAuthUri(string secret, string accountName) =>
        $"otpauth://totp/{Uri.EscapeDataString(Issuer)}:{Uri.EscapeDataString(accountName)}" +
        $"?secret={secret}&issuer={Uri.EscapeDataString(Issuer)}&algorithm=SHA1&digits=6&period=30";

    public bool TryVerify(string secret, string code, long? lastUsedStep, out long timeStep)
    {
        timeStep = 0;
        var totp = new Totp(Base32Encoding.ToBytes(secret)); // SHA-1, 30 s, 6 digits by default
        if (!totp.VerifyTotp(code, out var matched, Window))
            return false;

        if (lastUsedStep is not null && matched <= lastUsedStep)
            return false;

        timeStep = matched;
        return true;
    }
}
