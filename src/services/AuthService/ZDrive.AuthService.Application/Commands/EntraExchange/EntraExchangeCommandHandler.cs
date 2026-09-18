using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.AuthService.Domain.Enums;
using ZDrive.Shared.Exceptions;
using Entities = ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Commands.EntraExchange;

public sealed class EntraExchangeCommandHandler : IRequestHandler<EntraExchangeCommand, AuthTokenDto>
{
    // A federated session must not stay renewable indefinitely after access is
    // revoked on the Entra side — cap the refresh token independently of the
    // usual 30-day rotation window used for the password flow.
    private const int AbsoluteSessionHours = 24;

    private readonly IAuthDbContext _db;
    private readonly IEntraTokenValidator _entraTokenValidator;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;

    public EntraExchangeCommandHandler(
        IAuthDbContext db,
        IEntraTokenValidator entraTokenValidator,
        IJwtTokenGenerator jwtTokenGenerator)
    {
        _db = db;
        _entraTokenValidator = entraTokenValidator;
        _jwtTokenGenerator = jwtTokenGenerator;
    }

    public async Task<AuthTokenDto> Handle(EntraExchangeCommand request, CancellationToken cancellationToken)
    {
        var identity = await _entraTokenValidator.ValidateAsync(request.AccessToken, cancellationToken);

        var user = await FindMappedUserAsync(identity.TenantId, identity.ObjectId, cancellationToken);

        if (user is null)
            user = await CreateUserAsync(identity, cancellationToken);
        else
            user.LastLoginAt = DateTime.UtcNow; // persisted together with the new refresh token below

        return await IssueTokensAsync(user, cancellationToken);
    }

    private async Task<Entities.User?> FindMappedUserAsync(string tenantId, string objectId, CancellationToken ct)
    {
        var mapping = await _db.ExternalIdentities
            .Include(ei => ei.User)
            .FirstOrDefaultAsync(ei => ei.ProviderTenantId == tenantId && ei.ObjectId == objectId, ct);

        return mapping?.User;
    }

    private async Task<Entities.User> CreateUserAsync(EntraIdentity identity, CancellationToken ct)
    {
        var emailNormalized = identity.Email.ToLowerInvariant();

        // Legacy password accounts are intentionally not linked (owner decision):
        // an Entra sign-in landing on an email already used for a password
        // account is a conflict, not an auto-merge.
        var emailTakenByPasswordAccount = await _db.Users.AnyAsync(u => u.Email == emailNormalized, ct);
        if (emailTakenByPasswordAccount)
        {
            // The winner of a concurrent first login for the SAME identity can
            // commit between our mapping lookup (above, in Handle) and this
            // email check — its user then looks like a pre-existing password
            // account here. Re-read the mapping once before concluding it's a
            // real conflict; only throw if it still isn't ours.
            var mapping = await FindMappedUserAsync(identity.TenantId, identity.ObjectId, ct);
            if (mapping is not null)
                return mapping;

            throw new ConflictException($"A user with email '{emailNormalized}' already exists.");
        }

        var displayName = identity.DisplayName ?? emailNormalized.Split('@')[0];

        var tenant = new Entities.Tenant
        {
            Id = Guid.NewGuid(),
            Name = $"{displayName}'s Space"
        };

        var user = new Entities.User
        {
            Id = Guid.NewGuid(),
            Email = emailNormalized,
            PasswordHash = null,
            DisplayName = displayName,
            Role = Role.Owner,
            TenantId = tenant.Id,
            Tenant = tenant,
            LastLoginAt = DateTime.UtcNow
        };

        var externalIdentity = new Entities.ExternalIdentity
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            User = user,
            ProviderTenantId = identity.TenantId,
            ObjectId = identity.ObjectId
        };

        _db.Tenants.Add(tenant);
        _db.Users.Add(user);
        _db.ExternalIdentities.Add(externalIdentity);

        try
        {
            await _db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Two concurrent first logins for the same Entra identity: the unique
            // index on (ProviderTenantId, ObjectId) makes the loser's insert throw.
            // Remove()-ing entities still in the Added state just detaches them
            // (nothing was ever persisted), so the caller's later SaveChanges for
            // the refresh token doesn't try to re-insert them.
            _db.ExternalIdentities.Remove(externalIdentity);
            _db.Users.Remove(user);
            _db.Tenants.Remove(tenant);

            var mapping = await FindMappedUserAsync(identity.TenantId, identity.ObjectId, ct);
            if (mapping is not null)
                return mapping;

            // Not our own (tid, oid) race — a *different* concurrent Entra
            // identity may have grabbed this email instead. That's the same
            // conflict the pre-check above guards against, just discovered
            // after the fact rather than before.
            var emailNowTaken = await _db.Users.AnyAsync(u => u.Email == emailNormalized, ct);
            if (emailNowTaken)
                throw new ConflictException($"A user with email '{emailNormalized}' already exists.");

            throw;
        }

        return user;
    }

    private async Task<AuthTokenDto> IssueTokensAsync(Entities.User user, CancellationToken ct)
    {
        var absoluteExpiresAt = DateTime.UtcNow.AddHours(AbsoluteSessionHours);

        var refreshToken = new Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            Token = _jwtTokenGenerator.GenerateRefreshToken(),
            UserId = user.Id,
            ExpiresAt = absoluteExpiresAt,
            AbsoluteExpiresAt = absoluteExpiresAt
        };

        _db.RefreshTokens.Add(refreshToken);
        await _db.SaveChangesAsync(ct);

        var accessToken = _jwtTokenGenerator.GenerateAccessToken(user);

        return new AuthTokenDto(accessToken, refreshToken.Token, DateTime.UtcNow.AddMinutes(15));
    }
}
