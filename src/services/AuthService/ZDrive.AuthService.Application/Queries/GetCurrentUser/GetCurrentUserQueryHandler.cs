using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Queries.GetCurrentUser;

public sealed class GetCurrentUserQueryHandler : IRequestHandler<GetCurrentUserQuery, UserDto>
{
    private readonly IAuthDbContext _db;

    public GetCurrentUserQueryHandler(IAuthDbContext db) => _db = db;

    public async Task<UserDto> Handle(GetCurrentUserQuery request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        return new UserDto(
            user.Id,
            user.Email,
            user.DisplayName,
            user.AvatarUrl,
            user.Role.ToString(),
            user.TenantId,
            user.CreatedAt);
    }
}
