using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Commands.AddTag;

public sealed class AddTagCommandHandler : IRequestHandler<AddTagCommand, PhotoTagDto>
{
    private readonly IPhotoDbContext _db;

    public AddTagCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<PhotoTagDto> Handle(AddTagCommand request, CancellationToken cancellationToken)
    {
        // Owner/tenant filter is part of the lookup, not a separate check, so a
        // photo belonging to another user looks identical to a missing one (404).
        var photoExists = await _db.Photos.AnyAsync(
            p => p.Id == request.PhotoId && p.UserId == request.UserId && p.TenantId == request.TenantId,
            cancellationToken);
        if (!photoExists)
            throw new NotFoundException("Photo", request.PhotoId);

        var tag = new PhotoTag
        {
            Id = Guid.NewGuid(),
            PhotoId = request.PhotoId,
            Tag = request.Tag,
            Confidence = request.Confidence,
            Source = request.Source,
        };

        _db.PhotoTags.Add(tag);
        await _db.SaveChangesAsync(cancellationToken);

        return tag.ToDto();
    }
}
