using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.DisableTwoFactor;

public sealed class DisableTwoFactorCommandHandler : IRequestHandler<DisableTwoFactorCommand, AuthTokenDto>
{
    private readonly IAuthDbContext _db;
    private readonly IPasswordHasher _passwordHasher;
    private readonly TwoFactorVerifier _verifier;

    public DisableTwoFactorCommandHandler(IAuthDbContext db, IPasswordHasher passwordHasher, TwoFactorVerifier verifier)
    {
        _db = db;
        _passwordHasher = passwordHasher;
        _verifier = verifier;
    }

    public async Task<AuthTokenDto> Handle(DisableTwoFactorCommand request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        if (!user.TwoFactorEnabled)
            throw new ConflictException("Two-factor authentication is not enabled.");

        // One error for a wrong password, a wrong code and a refused (over-cap)
        // attempt, so the response is neither a password oracle nor a lockout
        // signal. The attempt is reserved first and counts toward the same
        // per-user cap as second-factor logins.
        var invalid = TwoFactorVerifier.Invalid("code", "Invalid password or code.");

        if (!await _verifier.TryReserveAttemptAsync(user.Id, cancellationToken))
            throw invalid;

        if (user.PasswordHash is null || !_passwordHasher.Verify(request.Password, user.PasswordHash))
            throw invalid;

        var validCode = request.Code.Length == 6 && request.Code.All(char.IsAsciiDigit)
            ? await _verifier.VerifyTotpAsync(user, request.Code, cancellationToken)
            : await _verifier.VerifyRecoveryCodeAsync(user, request.Code, cancellationToken);
        if (!validCode)
            throw invalid;

        user.TwoFactorSecretProtected = null;
        user.TwoFactorEnabledAt = null;
        user.TwoFactorSecretCreatedAt = null;
        _db.RecoveryCodes.RemoveRange(await _db.RecoveryCodes.Where(c => c.UserId == user.Id).ToListAsync(cancellationToken));
        // Disabling 2FA signs out every other session.
        var tokens = await _verifier.RotateSessionAsync(user, cancellationToken);

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            // The same code was submitted concurrently and lost the race.
            throw invalid;
        }

        await _verifier.RefundAttemptAsync(user.Id, cancellationToken);
        return tokens;
    }
}
