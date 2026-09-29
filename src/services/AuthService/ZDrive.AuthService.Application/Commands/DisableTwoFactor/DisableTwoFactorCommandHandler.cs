using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.DisableTwoFactor;

public sealed class DisableTwoFactorCommandHandler : IRequestHandler<DisableTwoFactorCommand>
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

    public async Task Handle(DisableTwoFactorCommand request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        if (!user.TwoFactorEnabled)
            throw new ConflictException("Two-factor authentication is not enabled.");

        if (user.PasswordHash is null || !_passwordHasher.Verify(request.Password, user.PasswordHash))
            throw TwoFactorVerifier.Invalid("password", "Invalid password.");

        var valid = request.Code.Length == 6 && request.Code.All(char.IsAsciiDigit)
            ? _verifier.VerifyTotp(user, request.Code)
            : await _verifier.VerifyRecoveryCodeAsync(user, request.Code, cancellationToken);
        if (!valid)
            throw TwoFactorVerifier.Invalid("code", "Invalid code.");

        user.TwoFactorSecretProtected = null;
        user.TwoFactorEnabledAt = null;
        user.TwoFactorLastUsedStep = null;
        _db.RecoveryCodes.RemoveRange(await _db.RecoveryCodes.Where(c => c.UserId == user.Id).ToListAsync(cancellationToken));

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            // The same code was submitted concurrently and lost the race.
            throw TwoFactorVerifier.Invalid("code", "Invalid code.");
        }
    }
}
