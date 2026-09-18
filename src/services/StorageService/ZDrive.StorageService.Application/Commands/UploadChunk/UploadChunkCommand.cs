using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.UploadChunk;

public sealed record UploadChunkCommand(
    Guid SessionId,
    int ChunkIndex,
    string ChunkHash,
    Stream Stream,
    // Set only by the shared (link-driven) upload flow, which has no JWT to
    // bind the session to — the grant's own (tenant, owner, fileId) stands
    // in, and a session belonging to a different file/owner must 404 exactly
    // like an unknown session id (see SharedStorageController's own grant
    // checks for why: nothing here should distinguish "wrong owner" from
    // "doesn't exist" for an anonymous caller).
    Guid? ExpectedTenantId = null,
    Guid? ExpectedUserId = null,
    Guid? ExpectedFileId = null) : IRequest<ChunkUploadResultDto>;
