using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;
using Entities = ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Commands.Login;

public sealed class LoginCommandHandler : IRequestHandler<LoginCommand, AuthTokenDto>
{
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

    public async Task<AuthTokenDto> Handle(LoginCommand request, CancellationToken cancellationToken)
    {
        var emailNormalized = request.Email.ToLowerInvariant();

        var user = await _db.Users
            .Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email == emailNormalized, cancellationToken)
            ?? throw new NotFoundException("User", emailNormalized);

        if (!_passwordHasher.Verify(request.Password, user.PasswordHash))
            throw new NotFoundException("User", emailNormalized); // Intentionally vague for security

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

        return new AuthTokenDto(accessToken, refreshToken.Token, DateTime.UtcNow.AddMinutes(15));
    }
}
