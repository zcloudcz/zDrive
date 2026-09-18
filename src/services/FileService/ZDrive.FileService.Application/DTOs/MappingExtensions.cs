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
        share.AllowDelete,
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

    // Anonymous share-link responses must not leak the owner's internal ids
    // or blob layout to an unauthenticated visitor. Same JSON SHAPE as the
    // authenticated response (every property still present — the deployed
    // Flutter client and any other consumer that assumes required fields
    // must keep working), only the sensitive VALUES are blanked. Used by
    // every anonymous shares/link/* handler that returns a FileDto/ShareDto
    // (GetShareByToken, ListSharedChildren, GetShareInfo, CreateSharedFolder,
    // CreateShareFileVersion) — one mapping, not one per endpoint.
    public static FileDto ToPublicDto(this FileDto dto) => dto with
    {
        UserId = Guid.Empty,
        TenantId = Guid.Empty,
        BlobPath = null
    };

    public static ShareDto ToPublicDto(this ShareDto dto) => dto with
    {
        SharedBy = Guid.Empty,
        LinkToken = string.Empty
    };
}
