using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetFileChangeBatch;

/// <summary>
/// Global (all users and tenants) page of the change log for in-process
/// consumers such as the photo ingest worker. Same read semantics as the
/// per-user feed (SHARE lock + hold-back, ADR 0001), but each file appears
/// once, with its CURRENT state, so the consumer converges on the latest
/// state instead of replaying event types.
/// </summary>
public sealed record GetFileChangeBatchQuery(long Cursor = 0, int Limit = 500) : IRequest<FileChangeBatchDto>;
