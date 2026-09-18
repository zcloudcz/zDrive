using MediatR;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Entities;
using ZDrive.StorageService.Domain.Enums;

namespace ZDrive.StorageService.Application.Commands.InitUpload;

public sealed class InitUploadCommandHandler : IRequestHandler<InitUploadCommand, UploadSessionDto>
{
    private readonly IStorageDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public InitUploadCommandHandler(IStorageDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    public async Task<UploadSessionDto> Handle(InitUploadCommand request, CancellationToken cancellationToken)
    {
        var session = new UploadSession
        {
            Id = Guid.NewGuid(),
            UserId = request.UserId,
            TenantId = request.TenantId,
            FileId = request.FileId,
            FileName = request.FileName,
            Status = UploadSessionStatus.Active,
            TotalChunks = request.TotalChunks,
            UploadedChunks = 0,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.AddHours(24),
            MaxBytes = request.MaxBytes,
            ReceivedBytes = 0
        };

        _db.UploadSessions.Add(session);
        await _db.SaveChangesAsync(cancellationToken);

        var sasUrl = _blobStorage.GenerateTempUploadSasUrl(session.Id, 0);

        return new UploadSessionDto(session.Id, sasUrl);
    }
}
