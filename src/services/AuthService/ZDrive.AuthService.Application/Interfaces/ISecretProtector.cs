namespace ZDrive.AuthService.Application.Interfaces;

/// <summary>Reversible at-rest protection for secrets that must be read back (TOTP seeds).</summary>
public interface ISecretProtector
{
    string Protect(string plaintext);
    string Unprotect(string protectedValue);
}
