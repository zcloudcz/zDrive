using System.Security.Cryptography;
using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;
using Entities = ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Commands.Login;

public sealed class LoginCommandHandler : IRequestHandler<LoginCommand, LoginResultDto>
{
    private static readonly TimeSpan ChallengeLifetime = TimeSpan.FromMinutes(5);

    private readonly IAuthDbContext _db;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;

    public LoginCommandHandler(
        IAuthDbContext db,
        IPasswordHasher passwordHasher,
        IJwtTokenGenerator jwtTokenGenerator)
    {
        _db = db;
        _passwordHasher = passwordHasher;
        _jwtTokenGenerator = jwtTokenGenerator;
    }

    public async Task<LoginResultDto> Handle(LoginCommand request, CancellationToken cancellationToken)
    {
        var emailNormalized = request.Email.ToLowerInvariant();

        var user = await _db.Users
            .Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email == emailNormalized, cancellationToken)
            ?? throw new NotFoundException("User", emailNormalized);

        // Entra-only accounts have no PasswordHash — fail exactly like a wrong
        // password so the response never reveals that the account is federated.
        if (user.PasswordHash is null || !_passwordHasher.Verify(request.Password, user.PasswordHash))
            throw new NotFoundException("User", emailNormalized); // Intentionally vague for security

        if (user.TwoFactorEnabled)
            return LoginResultDto.Challenge(await CreateChallengeAsync(user.Id, cancellationToken));

        user.LastLoginAt = DateTime.UtcNow;

        var refreshToken = new Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = _jwtTokenGenerator.GenerateRefreshToken(),
            UserId = user.Id,
            ExpiresAt = DateTime.UtcNow.AddDays(30)
        };

        _db.RefreshTokens.Add(refreshToken);
        await _db.SaveChangesAsync(cancellationToken);

        var accessToken = _jwtTokenGenerator.GenerateAccessToken(user);

        return LoginResultDto.FromTokens(
            new AuthTokenDto(accessToken, refreshToken.Token, DateTime.UtcNow.AddMinutes(15)));
    }

    private async Task<string> CreateChallengeAsync(Guid userId, CancellationToken cancellationToken)
    {
        // Housekeeping: drop this user's dead challenges (used, expired,
        // burned) and keep only the newest live ones, so rows cannot pile up.
        // Live ones otherwise stay: a second login (another device, or someone
        // who only knows the password) must not kill a challenge that is
        // being completed.
        var existing = await _db.TwoFactorChallenges
            .Where(c => c.UserId == userId)
            .OrderByDescending(c => c.CreatedAt)
            .ToListAsync(cancellationToken);
        var live = existing.Where(c => c.IsUsable).ToList();
        _db.TwoFactorChallenges.RemoveRange(existing.Except(live));
        _db.TwoFactorChallenges.RemoveRange(live.Skip(Entities.TwoFactorChallenge.MaxLivePerUser - 1));

        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        _db.TwoFactorChallenges.Add(new Entities.TwoFactorChallenge
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            TokenHash = TwoFactorVerifier.HashToken(token),
            ExpiresAt = DateTime.UtcNow.Add(ChallengeLifetime)
        });

        // A challenge being completed concurrently can change or vanish under
        // a housekeeping delete; that is benign — skip the delete, keep the
        // new challenge.
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                await _db.SaveChangesAsync(cancellationToken);
                return token;
            }
            catch (DbUpdateConcurrencyException ex) when (attempt < 5 && ex.Entries.All(e => e.State == EntityState.Deleted))
            {
                foreach (var entry in ex.Entries)
                    entry.State = EntityState.Detached;
            }
        }
    }
}
