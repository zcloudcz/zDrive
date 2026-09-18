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
    // Chunks are requested throughout the whole download, not just at the
    // start — a grant has to outlive the entire multi-GB transfer, not just
    // the time to fetch the first chunk. 6 hours covers even a slow one; the
    // client can also just ask for a fresh grant if this one expires mid-way.
    private static readonly TimeSpan GrantTtl = TimeSpan.FromHours(6);

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
        // error — production doesn't have this key set up yet.
        if (!_options.TryGetKey(out var key))
            throw new NotFoundException("Share", request.LinkToken);

        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);

        var file = await PublicShareAccess.FindWithinShareAsync(_db, share, request.FileId, cancellationToken);
        if (file is null || file.IsFolder || file.ManifestHash is null)
            throw new NotFoundException("FileNode", request.FileId);

        var expiresAt = DateTimeOffset.UtcNow.Add(GrantTtl);

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
