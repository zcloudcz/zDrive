using MediatR;

namespace ZDrive.AuthService.Application.Commands.UpdateProfile;

public sealed record UpdateProfileCommand(
    Guid UserId,
    string? DisplayName,
    string? AvatarUrl) : IRequest;
