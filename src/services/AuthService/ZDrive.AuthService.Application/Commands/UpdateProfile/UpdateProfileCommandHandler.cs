using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.AuthService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Application.Commands.UpdateProfile;

public sealed class UpdateProfileCommandHandler : IRequestHandler<UpdateProfileCommand>
{
    private readonly IAuthDbContext _db;

    public UpdateProfileCommandHandler(IAuthDbContext db) => _db = db;

    public async Task Handle(UpdateProfileCommand request, CancellationToken cancellationToken)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken)
            ?? throw new NotFoundException("User", request.UserId);

        if (request.DisplayName is not null)
            user.DisplayName = request.DisplayName;

        if (request.AvatarUrl is not null)
            user.AvatarUrl = request.AvatarUrl;

        await _db.SaveChangesAsync(cancellationToken);
    }
}
