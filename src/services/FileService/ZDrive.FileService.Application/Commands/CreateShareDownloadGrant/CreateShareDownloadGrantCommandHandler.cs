using MediatR;
using Microsoft.Extensions.Options;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;

public sealed class CreateShareDownloadGrantCommandHandler
    : IRequestHandler<CreateShareDownloadGrantCommand, ShareDownloadGrantDto>
{
    // StorageService validates a grant purely from its own signature and
    // expiry — it has no way to see FileService state, so it cannot tell
    // that the owner has since revoked the share, deleted the file, or
    // moved it out of the shared folder. The grant's TTL is therefore the
    // ONLY revocation window those actions get: however long it is, an
    // already-issued grant keeps working for that long regardless of what
    // happens on the FileService side afterwards. 1 hour bounds that window
    // to something a legitimate owner could live with, at the cost of the
    // client having to re-request a grant if a single chunk download runs
    // longer than that (each chunk is a separate request against the same
    // grant, so a fresh grant mid-transfer is a cheap, ordinary retry).
    private static readonly TimeSpan GrantTtl = TimeSpan.FromHours(1);

    private readonly IFileDbContext _db;
    private readonly ShareDownloadGrantOptions _options;

    public CreateShareDownloadGrantCommandHandler(IFileDbContext db, IOptions<ShareDownloadGrantOptions> options)
    {
        _db = db;
        _options = options.Value;
    }

    public async Task<ShareDownloadGrantDto> Handle(CreateShareDownloadGrantCommand request, CancellationToken cancellationToken)
    {
        // Fail closed: no key configured means the feature is off, not an
        // error — production doesn't have this key set up yet. Never echo
        // the link token as the NotFoundException key (see LoadShareAsync).
        if (!_options.TryGetKey(out var key))
            throw new NotFoundException("Share", "invalid");

        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);

        var file = await PublicShareAccess.FindWithinShareAsync(_db, share, request.FileId, cancellationToken);
        if (file is null || file.IsFolder || file.ManifestHash is null)
            throw new NotFoundException("FileNode", request.FileId);

        // Capped by the share's own expiry too: a grant must not outlive the
        // share it was issued from, or ExpiresAt on the Share becomes
        // decorative for anyone already holding a grant. ExpiresAt is stored
        // (and compared elsewhere, see Share.IsExpired) as a UTC clock value
        // with Kind left Unspecified by Npgsql — SpecifyKind instead of
        // ToUniversalTime, which would wrongly treat it as local time.
        var uncappedExpiry = DateTimeOffset.UtcNow.Add(GrantTtl);
        var shareExpiresAt = share.ExpiresAt.HasValue
            ? new DateTimeOffset(DateTime.SpecifyKind(share.ExpiresAt.Value, DateTimeKind.Utc))
            : (DateTimeOffset?)null;
        var expiresAt = shareExpiresAt.HasValue && shareExpiresAt.Value < uncappedExpiry
            ? shareExpiresAt.Value
            : uncappedExpiry;

        // file.TenantId/file.UserId are exactly the ids StorageController's
        // own User.GetTenantId() ?? userId fallback would have resolved for
        // the owner at upload time (that's how they ended up on the node) —
        // addressing the grant to them reaches the same blob path.
        var payload = new ShareDownloadGrant.Payload(
            file.TenantId, file.UserId, file.Id, file.ManifestHash, expiresAt);
        var grant = ShareDownloadGrant.Create(payload, key);

        return new ShareDownloadGrantDto(grant, expiresAt, file.Id, file.Name, file.SizeBytes, file.ManifestHash);
    }
}
