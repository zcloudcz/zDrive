using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Application.Common;

/// <summary>
/// A share download grant pins one manifest hash (one file version). Without
/// this check, a grant minted for version 1 of a file could be used to read
/// chunks that only exist in version 2 — the chunk hash alone doesn't prove
/// it belongs to the version the grant was issued for.
/// </summary>
public static class SharedChunkAccess
{
    public static bool IsChunkInManifest(ManifestDto manifest, string chunkHash) =>
        manifest.Chunks.Any(c => c.Hash == chunkHash);
}
