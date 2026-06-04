using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.RefreshToken;

public sealed class RefreshTokenCommandHandler : IRequestHandler<RefreshTokenCommand, AuthTokenDto>
{
    private readonly IAuthDbContext _db;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;

    public RefreshTokenCommandHandler(IAuthDbContext db, IJwtTokenGenerator jwtTokenGenerator)
    {
        _db = db;
        _jwtTokenGenerator = jwtTokenGenerator;
    }

    public async Task<AuthTokenDto> Handle(RefreshTokenCommand request, CancellationToken cancellationToken)
    {
        var existingToken = await _db.RefreshTokens
            .Include(rt => rt.User)
            .FirstOrDefaultAsync(rt => rt.Token == request.RefreshToken, cancellationToken)
            ?? throw new NotFoundException("RefreshToken", "(redacted)");

        if (!existingToken.IsActive)
            throw new NotFoundException("RefreshToken", "(redacted)");

        // Rotate: revoke old, issue new
        existingToken.RevokedAt = DateTime.UtcNow;
        var newRefreshTokenValue = _jwtTokenGenerator.GenerateRefreshToken();
        existingToken.ReplacedByToken = newRefreshTokenValue;

        var newRefreshToken = new Domain.Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = newRefreshTokenValue,
            UserId = existingToken.UserId,
            ExpiresAt = DateTime.UtcNow.AddDays(30)
        };

        _db.RefreshTokens.Add(newRefreshToken);
        await _db.SaveChangesAsync(cancellationToken);

        var accessToken = _jwtTokenGenerator.GenerateAccessToken(existingToken.User);

        return new AuthTokenDto(accessToken, newRefreshToken.Token, DateTime.UtcNow.AddMinutes(15));
    }
}
