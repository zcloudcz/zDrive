using System.Security.Cryptography;
using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateShare;

public sealed class CreateShareCommandHandler : IRequestHandler<CreateShareCommand, ShareDto>
{
    private readonly IFileDbContext _db;

    public CreateShareCommandHandler(IFileDbContext db) => _db = db;

    public async Task<ShareDto> Handle(CreateShareCommand request, CancellationToken cancellationToken)
    {
        // Verify file exists and belongs to the user.
        var file = await _db.FileNodes
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.UserId == request.UserId
                && !f.IsDeleted,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        var share = new Share
        {
            Id = Guid.NewGuid(),
            FileId = request.FileId,
            SharedBy = request.UserId,
            SharedWith = request.SharedWith,
            Permission = request.Permission,
            AllowDelete = request.AllowDelete,
            LinkToken = GenerateToken(),
            PasswordHash = request.Password is not null ? HashPassword(request.Password) : null,
            ExpiresAt = request.ExpiresAt
        };

        _db.Shares.Add(share);
        await _db.SaveChangesAsync(cancellationToken);

        return share.ToDto();
    }

    private static string GenerateToken()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    private static string HashPassword(string password)
    {
        // Simple SHA-256 hash for share passwords. Not for user auth (which uses Argon2).
        var bytes = System.Text.Encoding.UTF8.GetBytes(password);
        var hash = SHA256.HashData(bytes);
        return Convert.ToBase64String(hash);
    }
}
