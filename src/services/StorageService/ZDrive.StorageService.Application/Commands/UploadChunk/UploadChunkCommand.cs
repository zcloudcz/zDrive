using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.UploadChunk;

public sealed record UploadChunkCommand(
    Guid SessionId,
    int ChunkIndex,
    string ChunkHash,
    Stream Stream,
    // Always the caller's own ids — for an authenticated request, straight
    // from the JWT; for a shared request, the grant's owner ids. A session
    // belonging to someone else's (tenant, user) must 404 exactly like an
    // unknown session id, for both flows equally (this used to be checked
    // only for the shared flow — see the security review this closed).
    Guid CallerTenantId,
    Guid CallerUserId,
    // True only for the shared (link-driven) flow, so an authenticated
    // caller can never touch a shared session (minted from a grant, not a
    // JWT) and vice versa, even if ids happened to line up.
    bool IsShared = false,
    Guid? ExpectedFileId = null) : IRequest<ChunkUploadResultDto>;
