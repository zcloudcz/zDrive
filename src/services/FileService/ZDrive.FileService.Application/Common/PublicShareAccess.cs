using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Common;

/// <summary>
/// Shared "load and validate a public link share" logic used by every
/// anonymous shares/link/* endpoint (GetShareByToken, ListSharedChildren,
/// CreateShareDownloadGrant), so the expired/deleted/password/direct-share
/// rules live in exactly one place.
/// </summary>
public static class PublicShareAccess
{
    /// <summary>
    /// Loads the share for a link token and applies every anonymous-access
    /// rule. Throws NotFoundException for anything that should look like the
    /// link simply doesn't exist (expired, deleted root, unknown token, or a
    /// direct user-to-user share reusing this same LinkToken column — those
    /// are never meant to be reachable anonymously, so this must not even
    /// confirm they exist). Throws ForbiddenException only for the one case
    /// that legitimately needs a different response: a password-protected
    /// link, where the client needs to know to prompt for a password.
    /// </summary>
    public static async Task<Share> LoadShareAsync(IFileDbContext db, string linkToken, CancellationToken ct)
    {
        // NotFoundException embeds its "key" argument verbatim in the message
        // (see ZDrive.Shared.Exceptions.NotFoundException) — that message is
        // both the response body and a Warning log line, so the token itself
        // must never be passed as the key. It's a bearer credential for the
        // share; a fixed marker leaks nothing.
        var share = await db.Shares
            .AsNoTracking()
            .Include(s => s.File)
            .FirstOrDefaultAsync(s => s.LinkToken == linkToken, ct)
            ?? throw new NotFoundException("Share", "invalid");

        if (share.IsExpired || share.File.IsDeleted)
            throw new NotFoundException("Share", "invalid");

        if (share.SharedWith is not null)
            throw new NotFoundException("Share", "invalid");

        if (share.PasswordHash is not null)
            throw new ForbiddenException("This share is password protected.");

        return share;
    }

    // Fixed message, no token: this fires only after LoadShareAsync already
    // proved the link itself is valid (404 rules run first — see the
    // ordering note on every write endpoint), so there is nothing to hide by
    // varying the message; keeping it fixed just avoids ever accidentally
    // interpolating share/link state into a public error body.
    private const string ForbiddenMessage = "This share link does not allow this action.";

    /// <summary>
    /// Write access = Permission is Write or Admin (Admin behaves as Write on
    /// a link — see the contract). Called AFTER LoadShareAsync, so a 404 for
    /// an invalid link always wins over a 403 for a valid-but-read-only one.
    /// </summary>
    public static void RequireWrite(Share share)
    {
        if (share.Permission is not (Permission.Write or Permission.Admin))
            throw new ForbiddenException(ForbiddenMessage);
    }

    /// <summary>
    /// Delete is a separate, additive right (AllowDelete) — independent of
    /// Permission, so a Write link without AllowDelete still can't delete.
    /// </summary>
    public static void RequireDelete(Share share)
    {
        if (!share.AllowDelete)
            throw new ForbiddenException(ForbiddenMessage);
    }

    // FileNode only stores ParentId, no materialized path, so "is this node
    // inside the shared subtree" needs an upward walk rather than a single
    // query. Capped at 64 hops: a real folder tree from this app's own UI
    // never gets close to that, so hitting the cap means either a cycle
    // (data bug) or someone trying to break this by depth — either way,
    // treating it as "not found" is the right call.
    // ponytail: one DB round-trip per hop; a materialized path or nested-set
    // column would make this a single query if this ever shows up as hot.
    private const int MaxAncestorDepth = 64;

    /// <summary>
    /// Returns the node if it IS the shared root, or a non-deleted
    /// descendant of it (in the owner's own tenant), else null. Callers
    /// convert null to NotFoundException — never Forbidden, so a probe for
    /// node ids outside the share can't be distinguished from a wrong id.
    /// </summary>
    public static async Task<FileNode?> FindWithinShareAsync(
        IFileDbContext db, Share share, Guid nodeId, CancellationToken ct)
    {
        var root = share.File;
        if (nodeId == root.Id)
            return root;

        var node = await db.FileNodes.AsNoTracking().FirstOrDefaultAsync(
            f => f.Id == nodeId && f.TenantId == root.TenantId && f.UserId == root.UserId && !f.IsDeleted, ct);
        if (node is null)
            return null;

        var current = node;
        for (var i = 0; i < MaxAncestorDepth; i++)
        {
            if (current.ParentId == root.Id)
                return node;
            if (current.ParentId is null)
                return null;

            current = await db.FileNodes.AsNoTracking().FirstOrDefaultAsync(
                f => f.Id == current.ParentId && f.TenantId == root.TenantId && f.UserId == root.UserId && !f.IsDeleted, ct);
            if (current is null)
                return null;
        }

        return null;
    }
}
