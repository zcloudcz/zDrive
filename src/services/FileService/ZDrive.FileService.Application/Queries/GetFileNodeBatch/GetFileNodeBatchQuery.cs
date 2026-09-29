using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetFileNodeBatch;

/// <summary>
/// Keyset-paged (by node id) scan of every live, non-folder file node across
/// all users. Exists for one-time bootstrap of consumers of the change log,
/// which cannot see files created before the log existed (ADR 0001, "No
/// backfill"). Takes no feed lock: it reads plain node state.
/// </summary>
public sealed record GetFileNodeBatchQuery(Guid? AfterId = null, int Limit = 500) : IRequest<FileNodeBatchDto>;
