using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Entities;
using Entities = ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Commands.LoginTwoFactor;

public sealed class LoginTwoFactorCommandHandler : IRequestHandler<LoginTwoFactorCommand, AuthTokenDto>
{
    private const int MaxReserveRetries = 20;

    private readonly IAuthDbContext _db;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;
    private readonly TwoFactorVerifier _verifier;

    public LoginTwoFactorCommandHandler(
        IAuthDbContext db,
        IJwtTokenGenerator jwtTokenGenerator,
        TwoFactorVerifier verifier)
    {
        _db = db;
        _jwtTokenGenerator = jwtTokenGenerator;
        _verifier = verifier;
    }

    public async Task<AuthTokenDto> Handle(LoginTwoFactorCommand request, CancellationToken cancellationToken)
    {
        var invalidChallenge = TwoFactorVerifier.Invalid("challengeToken", "Invalid or expired challenge.");
        var invalidCode = TwoFactorVerifier.Invalid("code", "Invalid code.");

        var tokenHash = TwoFactorVerifier.HashToken(request.ChallengeToken);
        var challenge = await _db.TwoFactorChallenges
            .Include(c => c.User).ThenInclude(u => u.Tenant)
            .FirstOrDefaultAsync(c => c.TokenHash == tokenHash, cancellationToken);

        // Unknown, expired, used and exhausted challenges look the same.
        if (challenge is null || !challenge.IsUsable || !challenge.User.TwoFactorEnabled)
            throw invalidChallenge;

        // Reserve one of the challenge's attempts BEFORE the code is checked.
        // The counter is a concurrency token, so of any number of parallel
        // requests only one increment per value wins; the rest re-read and
        // either get the next slot or find the challenge burned. The cap is
        // therefore on evaluated guesses, not on failures noticed afterwards.
        if (!await ReserveChallengeAttemptAsync(challenge, cancellationToken))
            throw invalidChallenge;

        var user = challenge.User;

        // Per-user cap across challenges (and the disable endpoint). Over the
        // cap the answer is the ordinary invalid-code response.
        if (!await _verifier.TryReserveAttemptAsync(user.Id, cancellationToken))
            throw invalidCode;

        var valid = !string.IsNullOrWhiteSpace(request.Code)
            ? await _verifier.VerifyTotpAsync(user, request.Code.Trim(), cancellationToken)
            : await _verifier.VerifyRecoveryCodeAsync(user, request.RecoveryCode!, cancellationToken);

        // A wrong code changes nothing more: its attempts are already counted.
        if (!valid)
            throw invalidCode;

        challenge.UsedAt = DateTime.UtcNow;
        user.LastLoginAt = DateTime.UtcNow;

        var refreshToken = new Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = _jwtTokenGenerator.GenerateRefreshToken(),
            UserId = user.Id,
            ExpiresAt = DateTime.UtcNow.AddDays(30)
        };
        _db.RefreshTokens.Add(refreshToken);

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            // A concurrent request consumed the same challenge, TOTP step or
            // recovery code first (includes DbUpdateConcurrencyException).
            throw invalidCode;
        }

        // The successful attempt does not count against the user's cap.
        await _verifier.RefundAttemptAsync(user.Id, cancellationToken);

        var accessToken = _jwtTokenGenerator.GenerateAccessToken(user);
        return new AuthTokenDto(accessToken, refreshToken.Token, DateTime.UtcNow.AddMinutes(15));
    }

    private async Task<bool> ReserveChallengeAttemptAsync(TwoFactorChallenge challenge, CancellationToken ct)
    {
        for (var i = 0; i < MaxReserveRetries; i++)
        {
            if (!challenge.IsUsable)
                return false;

            challenge.FailedAttempts++;
            try
            {
                await _db.SaveChangesAsync(ct);
                return true;
            }
            catch (DbUpdateException ex)
            {
                // Lost the race (or the challenge was deleted): re-read its
                // current values and decide again.
                foreach (var entry in ex.Entries)
                {
                    if (entry.Entity != challenge)
                    {
                        entry.State = EntityState.Detached;
                        continue;
                    }

                    await entry.ReloadAsync(ct);
                    if (entry.State == EntityState.Detached)
                        return false;
                }
            }
        }

        return false;
    }
}
