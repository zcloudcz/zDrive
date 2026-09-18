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
            ExpiresAt = ToUtc(request.ExpiresAt)
        };

        _db.Shares.Add(share);
        await _db.SaveChangesAsync(cancellationToken);

        return share.ToDto();
    }

    // `expires_at` is a `timestamp with time zone`; Npgsql refuses to write a
    // DateTime whose Kind is not Utc and the request died with a 500. A JSON
    // value without an offset ("2026-09-27T00:00:00") deserializes as
    // Unspecified — clients that send it mean UTC by contract, so tag it;
    // a value that carried an offset arrives as Local and is converted.
    public static DateTime? ToUtc(DateTime? value) => value switch
    {
        null => null,
        { Kind: DateTimeKind.Utc } v => v,
        { Kind: DateTimeKind.Local } v => v.ToUniversalTime(),
        { } v => DateTime.SpecifyKind(v, DateTimeKind.Utc),
    };

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
