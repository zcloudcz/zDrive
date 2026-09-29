using System.Security.Cryptography;
using System.Text;
using FluentValidation;
using FluentValidation.Results;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Auth;

/// <summary>
/// Second-factor checks shared by login, enrollment and disable: TOTP and
/// recovery codes, the per-user attempt cap, and the session rotation that
/// follows a 2FA change. Mutates tracked entities; callers save.
/// </summary>
public sealed class TwoFactorVerifier
{
    // Crockford-style Base32 without I, L, O, U — no look-alike characters.
    private const string RecoveryAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    // 16 characters = 80 bits. That much entropy is what makes a fast salted
    // hash acceptable (see HashRecoveryCode); a shorter code would need a
    // deliberately slow one.
    private const int RecoveryCodeLength = 16;
    public const int RecoveryCodeCount = 10;

    private const int MaxSaveRetries = 20;

    private readonly IAuthDbContext _db;
    private readonly ITotpService _totp;
    private readonly ISecretProtector _protector;
    private readonly IJwtTokenGenerator _jwt;
    private readonly TwoFactorOptions _options;

    public TwoFactorVerifier(
        IAuthDbContext db,
        ITotpService totp,
        ISecretProtector protector,
        IJwtTokenGenerator jwt,
        IOptions<TwoFactorOptions> options)
    {
        _db = db;
        _totp = totp;
        _protector = protector;
        _jwt = jwt;
        _options = options.Value;
    }

    /// <summary>
    /// Counts one second-factor attempt against the user's window, atomically
    /// (optimistic concurrency, retried), BEFORE the code is checked — so
    /// parallel requests cannot all evaluate a guess past the cap. Returns
    /// false when the cap is reached (or contention never resolved).
    /// </summary>
    public Task<bool> TryReserveAttemptAsync(Guid userId, CancellationToken ct) =>
        UpdateGuardAsync(userId, guard =>
        {
            var now = DateTime.UtcNow;
            if (guard.FailureCount == 0 ||
                now - guard.FailureWindowStart >= TimeSpan.FromMinutes(_options.FailureWindowMinutes))
            {
                guard.FailureCount = 0;
                guard.FailureWindowStart = now;
            }

            if (guard.FailureCount >= _options.MaxFailedAttempts)
                return false;

            guard.FailureCount++;
            return true;
        }, ct);

    /// <summary>Gives back an attempt reserved for a request that then succeeded. Best effort.</summary>
    public async Task RefundAttemptAsync(Guid userId, CancellationToken ct) =>
        await UpdateGuardAsync(userId, guard =>
        {
            if (guard.FailureCount > 0)
                guard.FailureCount--;
            return true;
        }, ct);

    /// <summary>Creates the guard if needed and clears the replay-protection step (new secret).</summary>
    public async Task<bool> ResetStepAsync(Guid userId, CancellationToken ct) =>
        await UpdateGuardAsync(userId, guard =>
        {
            guard.LastUsedStep = null;
            return true;
        }, ct);

    /// <summary>Verifies a 6-digit TOTP code; on success records its step in the (tracked) guard.</summary>
    public async Task<bool> VerifyTotpAsync(User user, string code, CancellationToken ct)
    {
        if (user.TwoFactorSecretProtected is null)
            return false;

        var guard = await _db.TwoFactorGuards.FirstOrDefaultAsync(g => g.UserId == user.Id, ct);
        var secret = _protector.Unprotect(user.TwoFactorSecretProtected);
        if (!_totp.TryVerify(secret, code, guard?.LastUsedStep, out var step))
            return false;

        if (guard is null)
        {
            guard = new TwoFactorGuard { UserId = user.Id };
            _db.TwoFactorGuards.Add(guard);
        }

        guard.LastUsedStep = step;
        guard.Version = Guid.NewGuid();
        return true;
    }

    /// <summary>Consumes one unused recovery code; a code works exactly once.</summary>
    public async Task<bool> VerifyRecoveryCodeAsync(User user, string recoveryCode, CancellationToken ct)
    {
        var normalized = Normalize(recoveryCode);
        var candidates = await _db.RecoveryCodes
            .Where(c => c.UserId == user.Id && c.UsedAt == null)
            .ToListAsync(ct);

        // Every unused code is checked (no early exit) so timing does not
        // reveal which one matched.
        RecoveryCode? match = null;
        foreach (var candidate in candidates)
        {
            var expected = Convert.FromHexString(candidate.CodeHash);
            if (CryptographicOperations.FixedTimeEquals(HashRecoveryCode(candidate.Salt, normalized), expected))
                match = candidate;
        }

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
            var salt = RandomNumberGenerator.GetBytes(16);
            plain.Add(code);
            _db.RecoveryCodes.Add(new RecoveryCode
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Salt = Convert.ToHexString(salt),
                CodeHash = Convert.ToHexString(HashRecoveryCode(Convert.ToHexString(salt), Normalize(code)))
            });
        }

        return plain;
    }

    /// <summary>
    /// Ends every existing session of the user (their refresh tokens) and
    /// starts a fresh one for the device that just changed the 2FA setting.
    /// </summary>
    public async Task<AuthTokenDto> RotateSessionAsync(User user, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        foreach (var token in await _db.RefreshTokens
                     .Where(t => t.UserId == user.Id && t.RevokedAt == null && t.ExpiresAt > now)
                     .ToListAsync(ct))
        {
            token.RevokedAt = now;
        }

        var refresh = new RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = _jwt.GenerateRefreshToken(),
            UserId = user.Id,
            ExpiresAt = now.AddDays(30)
        };
        _db.RefreshTokens.Add(refresh);

        return new AuthTokenDto(_jwt.GenerateAccessToken(user), refresh.Token, now.AddMinutes(15));
    }

    public static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    public static ValidationException Invalid(string property, string message) =>
        new([new ValidationFailure(property, message)]);

    /// <summary>
    /// Load-or-create the user's guard, apply <paramref name="mutate"/>, save.
    /// A lost race (concurrency token, or a concurrent create) discards the
    /// attempt and retries on fresh data. Returns false if mutate refuses or
    /// contention never resolves.
    /// </summary>
    private async Task<bool> UpdateGuardAsync(Guid userId, Func<TwoFactorGuard, bool> mutate, CancellationToken ct)
    {
        for (var i = 0; i < MaxSaveRetries; i++)
        {
            var guard = await _db.TwoFactorGuards.FirstOrDefaultAsync(g => g.UserId == userId, ct);
            var created = guard is null;
            if (guard is null)
            {
                guard = new TwoFactorGuard { UserId = userId };
                _db.TwoFactorGuards.Add(guard);
            }

            if (!mutate(guard))
            {
                if (created)
                    _db.TwoFactorGuards.Remove(guard);
                return false;
            }

            guard.Version = Guid.NewGuid();
            try
            {
                await _db.SaveChangesAsync(ct);
                return true;
            }
            catch (DbUpdateException ex) // includes DbUpdateConcurrencyException
            {
                // Stale or duplicate: forget the tracked copy and read it again.
                foreach (var entry in ex.Entries)
                    entry.State = EntityState.Detached;
            }
        }

        return false;
    }

    // Shown as XXXX-XXXX-XXXX-XXXX; the dashes and case are cosmetic.
    private static string GenerateRecoveryCode()
    {
        var chars = new char[RecoveryCodeLength];
        for (var i = 0; i < chars.Length; i++)
            chars[i] = RecoveryAlphabet[RandomNumberGenerator.GetInt32(RecoveryAlphabet.Length)];
        var s = new string(chars);
        return $"{s[..4]}-{s[4..8]}-{s[8..12]}-{s[12..]}";
    }

    private static string Normalize(string code) =>
        new string(code.Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();

    // Salted SHA-256, not Argon2: the codes are 80 bits of CSPRNG output, so
    // offline guessing is infeasible even with a fast hash, and the per-code
    // salt stops precomputation. Argon2 would cost ~10 slow verifies per
    // attempt (every unused code is checked) — a CPU-exhaustion lever for
    // nothing gained.
    private static byte[] HashRecoveryCode(string saltHex, string normalizedCode) =>
        SHA256.HashData(Convert.FromHexString(saltHex).Concat(Encoding.UTF8.GetBytes(normalizedCode)).ToArray());
}
