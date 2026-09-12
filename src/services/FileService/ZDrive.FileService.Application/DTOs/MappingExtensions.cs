using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Application.DTOs;

public static class MappingExtensions
{
    public static FileDto ToDto(this FileNode node) => new(
        node.Id,
        node.UserId,
        node.TenantId,
        node.ParentId,
        node.Name,
        node.IsFolder,
        node.SizeBytes,
        node.MimeType,
        node.BlobPath,
        node.ManifestHash,
        node.IsDeleted,
        node.DeletedAt,
        node.CreatedAt,
        node.UpdatedAt);

    public static ShareDto ToDto(this Share share) => new(
        share.Id,
        share.FileId,
        share.SharedBy,
        share.SharedWith,
        share.Permission.ToString(),
        share.LinkToken,
        share.ExpiresAt,
        share.CreatedAt);

    public static FileVersionDto ToDto(this FileVersion version) => new(
        version.Id,
        version.FileId,
        version.VersionNumber,
        version.BlobVersionId,
        version.SizeBytes,
        version.ManifestHash,
        version.CreatedBy,
        version.Comment,
        version.CreatedAt);

    public static FileChangeDto ToDto(this FileChange change) => new(
        change.Id,
        change.FileId,
        change.Type.ToString(),
        change.OccurredAt);
}
