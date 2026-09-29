using MediatR;

namespace ZDrive.FileService.Application.Queries.GetFileChangeHead;

/// <summary>
/// Safe head of the global change log (see FileChangeFeedReader.ReadSafeHeadAsync).
/// Used by in-process consumers that bootstrap from current node state.
/// </summary>
public sealed record GetFileChangeHeadQuery : IRequest<long>;
