using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using Entities = ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Commands.LoginTwoFactor;

public sealed class LoginTwoFactorCommandHandler : IRequestHandler<LoginTwoFactorCommand, AuthTokenDto>
{
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
        var tokenHash = TwoFactorVerifier.HashToken(request.ChallengeToken);
        var challenge = await _db.TwoFactorChallenges
            .Include(c => c.User).ThenInclude(u => u.Tenant)
            .FirstOrDefaultAsync(c => c.TokenHash == tokenHash, cancellationToken);

        // Unknown, expired, used and exhausted challenges look the same.
        if (challenge is null || !challenge.IsUsable || !challenge.User.TwoFactorEnabled)
            throw TwoFactorVerifier.Invalid("challengeToken", "Invalid or expired challenge.");

        var user = challenge.User;
        var valid = !string.IsNullOrWhiteSpace(request.Code)
            ? _verifier.VerifyTotp(user, request.Code.Trim())
            : await _verifier.VerifyRecoveryCodeAsync(user, request.RecoveryCode!, cancellationToken);

        if (!valid)
        {
            // Only the attempt counter is persisted; nothing else changed on failure.
            challenge.FailedAttempts++;
            await _db.SaveChangesAsync(cancellationToken);
            throw TwoFactorVerifier.Invalid("code", "Invalid code.");
        }

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
        catch (DbUpdateConcurrencyException)
        {
            // A concurrent request consumed the same challenge, TOTP step or
            // recovery code first.
            throw TwoFactorVerifier.Invalid("code", "Invalid code.");
        }

        var accessToken = _jwtTokenGenerator.GenerateAccessToken(user);
        return new AuthTokenDto(accessToken, refreshToken.Token, DateTime.UtcNow.AddMinutes(15));
    }
}
