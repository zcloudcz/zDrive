using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.UploadChunk;

public sealed record UploadChunkCommand(
    Guid SessionId,
    int ChunkIndex,
    string ChunkHash,
    Stream Stream) : IRequest<ChunkUploadResultDto>;
