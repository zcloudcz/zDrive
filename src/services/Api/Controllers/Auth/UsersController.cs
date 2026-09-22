using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.AuthService.Application.Commands.UpdateProfile;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Application.Queries.GetCurrentUser;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;

namespace ZDrive.Api.Controllers.Auth;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
public sealed class UsersController : ControllerBase
{
    private readonly IMediator _mediator;

    public UsersController(IMediator mediator) => _mediator = mediator;

    [HttpGet("me")]
    [ProducesResponseType(typeof(ApiResponse<UserDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetCurrentUser(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new GetCurrentUserQuery(userId), ct);
        return Ok(ApiResponse<UserDto>.Ok(result));
    }

    [HttpPut("me")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        await _mediator.Send(new UpdateProfileCommand(userId, request.DisplayName, request.AvatarUrl), ct);
        return NoContent();
    }
}

public sealed record UpdateProfileRequest(string? DisplayName, string? AvatarUrl);
