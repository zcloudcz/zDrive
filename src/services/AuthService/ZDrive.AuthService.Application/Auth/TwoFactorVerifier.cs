using System.Security.Cryptography;
using System.Text;
using FluentValidation;
using FluentValidation.Results;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Auth;

/// <summary>
/// Checks a TOTP or recovery code against a user's 2FA state. Mutates the
/// tracked entities (last used step / recovery code UsedAt) on success; the
/// caller saves.
/// </summary>
public sealed class TwoFactorVerifier
{
    // Crockford-style Base32 without I, L, O, U — no look-alike characters.
    private const string RecoveryAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    private const int RecoveryCodeLength = 10;
    public const int RecoveryCodeCount = 10;

    private readonly IAuthDbContext _db;
    private readonly ITotpService _totp;
    private readonly ISecretProtector _protector;

    public TwoFactorVerifier(IAuthDbContext db, ITotpService totp, ISecretProtector protector)
    {
        _db = db;
        _totp = totp;
        _protector = protector;
    }

    /// <summary>Verifies a 6-digit TOTP code against the user's stored secret.</summary>
    public bool VerifyTotp(User user, string code)
    {
        if (user.TwoFactorSecretProtected is null)
            return false;

        var secret = _protector.Unprotect(user.TwoFactorSecretProtected);
        if (!_totp.TryVerify(secret, code, user.TwoFactorLastUsedStep, out var step))
            return false;

        user.TwoFactorLastUsedStep = step;
        return true;
    }

    /// <summary>Consumes one unused recovery code; a code works exactly once.</summary>
    public async Task<bool> VerifyRecoveryCodeAsync(User user, string recoveryCode, CancellationToken ct)
    {
        var hash = HashRecoveryCode(recoveryCode);
        var match = await _db.RecoveryCodes
            .FirstOrDefaultAsync(c => c.UserId == user.Id && c.CodeHash == hash && c.UsedAt == null, ct);
        if (match is null)
            return false;

        match.UsedAt = DateTime.UtcNow;
        return true;
    }

    /// <summary>Replaces all of the user's recovery codes; returns the new plain codes.</summary>
    public async Task<IReadOnlyList<string>> ReplaceRecoveryCodesAsync(User user, CancellationToken ct)
    {
        _db.RecoveryCodes.RemoveRange(await _db.RecoveryCodes.Where(c => c.UserId == user.Id).ToListAsync(ct));

        var plain = new List<string>(RecoveryCodeCount);
        for (var i = 0; i < RecoveryCodeCount; i++)
        {
            var code = GenerateRecoveryCode();
            plain.Add(code);
            _db.RecoveryCodes.Add(new RecoveryCode
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                CodeHash = HashRecoveryCode(code)
            });
        }

        return plain;
    }

    public static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    public static ValidationException Invalid(string property, string message) =>
        new([new ValidationFailure(property, message)]);

    // Shown as XXXXX-XXXXX; the dash and case are cosmetic.
    private static string GenerateRecoveryCode()
    {
        var chars = new char[RecoveryCodeLength];
        for (var i = 0; i < chars.Length; i++)
            chars[i] = RecoveryAlphabet[RandomNumberGenerator.GetInt32(RecoveryAlphabet.Length)];
        return $"{new string(chars, 0, 5)}-{new string(chars, 5, 5)}";
    }

    private static string HashRecoveryCode(string code) =>
        HashToken(new string(code.Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant());
}
