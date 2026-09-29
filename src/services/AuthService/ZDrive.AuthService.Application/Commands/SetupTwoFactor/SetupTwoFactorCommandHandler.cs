using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.SetupTwoFactor;

public sealed class SetupTwoFactorCommandHandler : IRequestHandler<SetupTwoFactorCommand, TwoFactorSetupDto>
{
    private readonly IAuthDbContext _db;
    private readonly ITotpService _totp;
    private readonly ISecretProtector _protector;

    public SetupTwoFactorCommandHandler(IAuthDbContext db, ITotpService totp, ISecretProtector protector)
    {
        _db = db;
        _totp = totp;
        _protector = protector;
    }

    public async Task<TwoFactorSetupDto> Handle(SetupTwoFactorCommand request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        // Entra accounts get MFA from Entra (docs/gaps/entra-external-id.md).
        if (user.PasswordHash is null)
            throw new ForbiddenException("Two-factor authentication is not available for this account.");

        if (user.TwoFactorEnabled)
            throw new ConflictException("Two-factor authentication is already enabled.");

        // Re-running setup before confirming replaces the pending secret.
        var secret = _totp.GenerateSecret();
        user.TwoFactorSecretProtected = _protector.Protect(secret);
        await _db.SaveChangesAsync(cancellationToken);

        return new TwoFactorSetupDto(secret, _totp.BuildOtpAuthUri(secret, user.Email));
    }
}
