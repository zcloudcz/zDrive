using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Queries.GetMemories;

public sealed record GetMemoriesQuery(Guid UserId) : IRequest<List<MemoryDto>>;
