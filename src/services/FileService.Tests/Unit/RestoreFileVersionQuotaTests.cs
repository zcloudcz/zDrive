using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;
using ZDrive.FileService.Application.Commands.RestoreFileVersion;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Application.Services;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Restoring an old version records a NEW file_versions row carrying the
/// source's SizeBytes (CLAUDE.md "Blob versioning": restore-as-new-version).
/// That row is counted by the usage SUM exactly like a fresh upload, so it
/// must clear the same quota check — this is what these tests pin down.
/// </summary>
[Trait("Category", "Unit")]
public sealed class RestoreFileVersionQuotaTests
{
    [Fact]
    public async Task Handle_RestoreWouldExceedQuota_ThrowsQuotaExceeded()
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var file = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = userId, Name = "f.txt", IsFolder = false };
        db.FileNodes.Add(file);
        var v1 = new FileVersion { Id = Guid.NewGuid(), FileId = file.Id, VersionNumber = 1, BlobVersionId = "v1", SizeBytes = 90, CreatedBy = userId };
        db.FileVersions.Add(v1);
        db.SaveChanges();
        // Current usage (90) is already within 10 bytes of the limit — restoring
        // v1 again would add another 90-byte row and blow past it.
        var quota = new StorageQuota(db, Options.Create(new StorageOptions { DefaultUserQuotaBytes = 100 }));
        var handler = new RestoreFileVersionCommandHandler(db, Options.Create(new VersioningOptions()), quota);

        var act = () => handler.Handle(
            new RestoreFileVersionCommand(tenantId, userId, file.Id, v1.Id), CancellationToken.None);

        await act.Should().ThrowAsync<QuotaExceededException>();
    }
}
