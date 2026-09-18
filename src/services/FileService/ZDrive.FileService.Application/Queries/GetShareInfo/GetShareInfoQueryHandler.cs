using MediatR;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Enums;

namespace ZDrive.FileService.Application.Queries.GetShareInfo;

public sealed class GetShareInfoQueryHandler : IRequestHandler<GetShareInfoQuery, ShareInfoDto>
{
    private readonly IFileDbContext _db;
    private readonly IStorageQuota _quota;

    public GetShareInfoQueryHandler(IFileDbContext db, IStorageQuota quota)
    {
        _db = db;
        _quota = quota;
    }

    public async Task<ShareInfoDto> Handle(GetShareInfoQuery request, CancellationToken cancellationToken)
    {
        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);

        // Quota is reported for the OWNER of the shared root, not the caller
        // (an anonymous visitor has no quota of their own) — same ids an
        // upload through this link would be charged against. Only surfaced
        // to a Write link: a Read link's visitor has no reason to learn how
        // full the owner's account is, so it stays null for them.
        ShareQuotaDto? quota = null;
        if (share.Permission is Permission.Write or Permission.Admin)
        {
            var usage = await _quota.GetUsageAsync(share.File.TenantId, share.File.UserId, claimLimit: null, cancellationToken);
            quota = new ShareQuotaDto(usage.LimitBytes, usage.UsedBytes);
        }

        return new ShareInfoDto(
            share.Permission.ToString(),
            share.AllowDelete,
            share.ExpiresAt,
            share.File.ToDto(),
            quota);
    }
}
