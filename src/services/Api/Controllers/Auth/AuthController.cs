using MediatR;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.Commands.EntraExchange;
using ZDrive.AuthService.Application.Commands.Login;
using ZDrive.AuthService.Application.Commands.LoginTwoFactor;
using ZDrive.AuthService.Application.Commands.RefreshToken;
using ZDrive.AuthService.Application.Commands.Register;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.Api.Controllers.Auth;

[ApiController]
[Route("api/v1/[controller]")]
public sealed class AuthController : ControllerBase
{
    private readonly IMediator _mediator;
    private readonly EntraOptions _entraOptions;

    public AuthController(IMediator mediator, IOptions<EntraOptions> entraOptions)
    {
        _mediator = mediator;
        _entraOptions = entraOptions.Value;
    }

    [HttpPost("register")]
    [ProducesResponseType(typeof(ApiResponse<AuthTokenDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Register([FromBody] RegisterCommand command, CancellationToken ct)
    {
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<AuthTokenDto>.Ok(result));
    }

    [HttpPost("login")]
    [ProducesResponseType(typeof(ApiResponse<LoginResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Login([FromBody] LoginCommand command, CancellationToken ct)
    {
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<LoginResultDto>.Ok(result));
    }

    [HttpPost("login/2fa")]
    [ProducesResponseType(typeof(ApiResponse<AuthTokenDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> LoginTwoFactor([FromBody] LoginTwoFactorCommand command, CancellationToken ct)
    {
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<AuthTokenDto>.Ok(result));
    }

    [HttpPost("refresh")]
    [ProducesResponseType(typeof(ApiResponse<AuthTokenDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Refresh([FromBody] RefreshTokenCommand command, CancellationToken ct)
    {
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<AuthTokenDto>.Ok(result));
    }

    [HttpPost("entra")]
    [ProducesResponseType(typeof(ApiResponse<AuthTokenDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> EntraExchange([FromBody] EntraExchangeCommand command, CancellationToken ct)
    {
        // Opt-in feature: until a deployment has an Entra app registration
        // wired up, hide the endpoint entirely instead of answering with a
        // config error that would leak that the feature half-exists.
        if (!_entraOptions.Enabled)
            return NotFound();

        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<AuthTokenDto>.Ok(result));
    }
}
