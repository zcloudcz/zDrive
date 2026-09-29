using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.PhotoService.Application.Commands.DismissMemory;
using ZDrive.PhotoService.Application.Queries.GetMemories;
using ZDrive.Shared.Auth;

namespace ZDrive.Api.Controllers.Photos;

[ApiController]
[Route("api/v1/memories")]
[Authorize]
public class MemoriesController : ControllerBase
{
    private readonly IMediator _mediator;

    public MemoriesController(IMediator mediator) => _mediator = mediator;

    [HttpGet]
    public async Task<IActionResult> GetAll(CancellationToken ct)
    {
        var result = await _mediator.Send(new GetMemoriesQuery(User.GetUserId()), ct);
        return Ok(result);
    }

    [HttpPost("{id:guid}/dismiss")]
    public async Task<IActionResult> Dismiss(Guid id, CancellationToken ct)
    {
        await _mediator.Send(new DismissMemoryCommand(User.GetUserId(), id), ct);
        return NoContent();
    }
}
