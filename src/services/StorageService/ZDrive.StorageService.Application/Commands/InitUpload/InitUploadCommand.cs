using MediatR;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Commands.InitUpload;

public sealed record InitUploadCommand(
    Guid UserId,
    Guid TenantId,
    Guid FileId,
    string FileName,
    int TotalChunks,
    long? MaxBytes = null,
    bool IsShared = false,
    // The owner's quota headroom AT GRANT TIME, carried in the ShareUploadGrant
    // (StorageService cannot see FileService's quota otherwise). Only checked
    // for a shared session — see InitUploadCommandHandler.
    long? QuotaRemainingBytes = null) : IRequest<UploadSessionDto>;
