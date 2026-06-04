using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Enums;
using ZDrive.Shared.Exceptions;
using Entities = ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Commands.Register;

public sealed class RegisterCommandHandler : IRequestHandler<RegisterCommand, AuthTokenDto>
{
    private readonly IAuthDbContext _db;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;

    public RegisterCommandHandler(
        IAuthDbContext db,
        IPasswordHasher passwordHasher,
        IJwtTokenGenerator jwtTokenGenerator)
    {
        _db = db;
        _passwordHasher = passwordHasher;
        _jwtTokenGenerator = jwtTokenGenerator;
    }

    public async Task<AuthTokenDto> Handle(RegisterCommand request, CancellationToken cancellationToken)
    {
        var emailNormalized = request.Email.ToLowerInvariant();

        var exists = await _db.Users.AnyAsync(u => u.Email == emailNormalized, cancellationToken);
        if (exists)
            throw new ConflictException($"A user with email '{emailNormalized}' already exists.");

        // Every new registration gets an implicit personal tenant.
        var tenant = new Entities.Tenant
        {
            Id = Guid.NewGuid(),
            Name = $"{request.DisplayName}'s Space"
        };

        var user = new Entities.User
        {
            Id = Guid.NewGuid(),
            Email = emailNormalized,
            PasswordHash = _passwordHasher.Hash(request.Password),
            DisplayName = request.DisplayName,
            Role = Role.Owner,
            TenantId = tenant.Id,
            Tenant = tenant
        };

        var refreshToken = new Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = _jwtTokenGenerator.GenerateRefreshToken(),
            UserId = user.Id,
            ExpiresAt = DateTime.UtcNow.AddDays(30)
        };

        _db.Tenants.Add(tenant);
        _db.Users.Add(user);
        _db.RefreshTokens.Add(refreshToken);
        await _db.SaveChangesAsync(cancellationToken);

        var accessToken = _jwtTokenGenerator.GenerateAccessToken(user);

        return new AuthTokenDto(accessToken, refreshToken.Token, DateTime.UtcNow.AddMinutes(15));
    }
}
