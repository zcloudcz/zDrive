using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Application.Interfaces;

public interface IJwtTokenGenerator
{
    string GenerateAccessToken(User user);
    string GenerateRefreshToken();
}
