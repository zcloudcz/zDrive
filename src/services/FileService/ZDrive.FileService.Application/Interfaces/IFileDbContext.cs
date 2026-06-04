using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Application.Interfaces;

public interface IFileDbContext
{
    DbSet<FileNode> FileNodes { get; }
    DbSet<FileVersion> FileVersions { get; }
    DbSet<Share> Shares { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
