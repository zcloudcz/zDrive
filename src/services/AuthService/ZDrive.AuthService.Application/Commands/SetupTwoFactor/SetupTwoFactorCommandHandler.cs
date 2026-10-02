using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.SetupTwoFactor;

public sealed class SetupTwoFactorCommandHandler : IRequestHandler<SetupTwoFactorCommand, TwoFactorSetupDto>
{
    // A pending (unconfirmed) secret is handed out again within this time, so
    // a repeated or racing setup call cannot invalidate the QR code the user
    // is scanning.
    private static readonly TimeSpan PendingSecretReuse = TimeSpan.FromMinutes(10);

    private readonly IAuthDbContext _db;
    private readonly IPasswordHasher _passwordHasher;
    private readonly ITotpService _totp;
    private readonly ISecretProtector _protector;
    private readonly TwoFactorVerifier _verifier;

    public SetupTwoFactorCommandHandler(
        IAuthDbContext db,
        IPasswordHasher passwordHasher,
        ITotpService totp,
        ISecretProtector protector,
        TwoFactorVerifier verifier)
    {
        _db = db;
        _passwordHasher = passwordHasher;
        _totp = totp;
        _protector = protector;
        _verifier = verifier;
    }

    public async Task<TwoFactorSetupDto> Handle(SetupTwoFactorCommand request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        // Entra accounts get MFA from Entra (docs/gaps/entra-external-id.md).
        if (user.PasswordHash is null)
            throw new ForbiddenException("Two-factor authentication is not available for this account.");

        if (!_passwordHasher.Verify(request.Password, user.PasswordHash))
            throw TwoFactorVerifier.Invalid("password", "Invalid password.");

        if (user.TwoFactorEnabled)
            throw new ConflictException("Two-factor authentication is already enabled.");

        var now = DateTime.UtcNow;
        if (user.TwoFactorSecretProtected is not null &&
            user.TwoFactorSecretCreatedAt is { } created && now - created < PendingSecretReuse)
        {
            var pending = _protector.Unprotect(user.TwoFactorSecretProtected);
            return new TwoFactorSetupDto(pending, _totp.BuildOtpAuthUri(pending, user.Email));
        }

        // A new secret starts with a clean replay-protection step.
        if (!await _verifier.ResetStepAsync(user.Id, cancellationToken))
            throw new ConflictException("Two-factor setup is busy. Please try again.");

        var secret = _totp.GenerateSecret();
        user.TwoFactorSecretProtected = _protector.Protect(secret);
        user.TwoFactorSecretCreatedAt = now;
        await _db.SaveChangesAsync(cancellationToken);

        return new TwoFactorSetupDto(secret, _totp.BuildOtpAuthUri(secret, user.Email));
    }
}
