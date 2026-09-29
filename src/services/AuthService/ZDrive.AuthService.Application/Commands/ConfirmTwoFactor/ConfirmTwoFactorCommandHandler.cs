using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.ConfirmTwoFactor;

public sealed class ConfirmTwoFactorCommandHandler : IRequestHandler<ConfirmTwoFactorCommand, RecoveryCodesDto>
{
    private readonly IAuthDbContext _db;
    private readonly TwoFactorVerifier _verifier;

    public ConfirmTwoFactorCommandHandler(IAuthDbContext db, TwoFactorVerifier verifier)
    {
        _db = db;
        _verifier = verifier;
    }

    public async Task<RecoveryCodesDto> Handle(ConfirmTwoFactorCommand request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        if (user.PasswordHash is null)
            throw new ForbiddenException("Two-factor authentication is not available for this account.");

        if (user.TwoFactorEnabled)
            throw new ConflictException("Two-factor authentication is already enabled.");

        if (user.TwoFactorSecretProtected is null)
            throw TwoFactorVerifier.Invalid("code", "Two-factor setup has not been started.");

        if (!_verifier.VerifyTotp(user, request.Code))
            throw TwoFactorVerifier.Invalid("code", "Invalid code.");

        user.TwoFactorEnabledAt = DateTime.UtcNow;
        var recoveryCodes = await _verifier.ReplaceRecoveryCodesAsync(user, cancellationToken);
        await _db.SaveChangesAsync(cancellationToken);

        return new RecoveryCodesDto(recoveryCodes);
    }
}
