using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.AuthService.Application.Commands.ConfirmTwoFactor;
using ZDrive.AuthService.Application.Commands.DisableTwoFactor;
using ZDrive.AuthService.Application.Commands.SetupTwoFactor;
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

    [HttpPost("me/2fa/setup")]
    [ProducesResponseType(typeof(ApiResponse<TwoFactorSetupDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> SetupTwoFactor(CancellationToken ct)
    {
        var result = await _mediator.Send(new SetupTwoFactorCommand(User.GetUserId()), ct);
        return Ok(ApiResponse<TwoFactorSetupDto>.Ok(result));
    }

    [HttpPost("me/2fa/confirm")]
    [ProducesResponseType(typeof(ApiResponse<RecoveryCodesDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> ConfirmTwoFactor([FromBody] ConfirmTwoFactorRequest request, CancellationToken ct)
    {
        var result = await _mediator.Send(new ConfirmTwoFactorCommand(User.GetUserId(), request.Code), ct);
        return Ok(ApiResponse<RecoveryCodesDto>.Ok(result));
    }

    [HttpPost("me/2fa/disable")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DisableTwoFactor([FromBody] DisableTwoFactorRequest request, CancellationToken ct)
    {
        await _mediator.Send(new DisableTwoFactorCommand(User.GetUserId(), request.Password, request.Code), ct);
        return NoContent();
    }
}

public sealed record UpdateProfileRequest(string? DisplayName, string? AvatarUrl);

public sealed record ConfirmTwoFactorRequest(string Code);

public sealed record DisableTwoFactorRequest(string Password, string Code);
