namespace ZDrive.StorageService.Application.DTOs;

/// <summary>
/// The chunk manifest, re-served through the normal controller pipeline
/// (camelCase, wrapped in ApiResponse&lt;T&gt;) so web clients can read it
/// without a cross-origin fetch straight to blob storage. See
/// GetManifestQueryHandler.
/// </summary>
public sealed record ManifestDto(long TotalSize, List<ManifestChunkDto> Chunks);

public sealed record ManifestChunkDto(string Hash, int Index);
