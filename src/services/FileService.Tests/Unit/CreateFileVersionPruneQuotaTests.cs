using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateFileVersion;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Application.Services;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// The quota check must be net of what this same write prunes: a user
/// sitting at the limit must still be able to replace a file whose oldest
/// (about to be pruned) version is at least as large as the new one.
/// MaxVersionsPerFile = 1 forces every new version to prune all existing
/// ones for that file, isolating the "net of pruned bytes" behavior.
/// </summary>
[Trait("Category", "Unit")]
public sealed class CreateFileVersionPruneQuotaTests
{
    private static (CreateFileVersionCommandHandler Handler, InMemoryFileDbContext Db, FileNode File, Guid TenantId, Guid UserId)
        CreateSut(long quotaLimit, long existingVersionSizeBytes)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var file = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = userId, Name = "f.txt", IsFolder = false };
        db.FileNodes.Add(file);
        db.FileVersions.Add(new FileVersion
        {
            Id = Guid.NewGuid(), FileId = file.Id, VersionNumber = 1,
            BlobVersionId = "v1", SizeBytes = existingVersionSizeBytes, CreatedBy = userId
        });
        db.SaveChanges();

        var versioning = Options.Create(new VersioningOptions { MaxVersionsPerFile = 1 });
        var quota = new StorageQuota(db, Options.Create(new StorageOptions { DefaultUserQuotaBytes = quotaLimit }));
        var handler = new CreateFileVersionCommandHandler(db, versioning, quota);

        return (handler, db, file, tenantId, userId);
    }

    [Fact]
    public async Task Handle_AtLimit_NewVersionNoBiggerThanPrunedOne_Accepted()
    {
        // Usage is already at the 100-byte limit; the write prunes the
        // existing 100-byte version, so the new 100-byte version is a wash.
        var (handler, db, file, tenantId, userId) = CreateSut(quotaLimit: 100, existingVersionSizeBytes: 100);
        var command = new CreateFileVersionCommand(tenantId, userId, file.Id, "v2", SizeBytes: 100, null, null);

        var result = await handler.Handle(command, CancellationToken.None);

        result.SizeBytes.Should().Be(100);
        db.FileVersions.Should().ContainSingle(v => v.FileId == file.Id && v.Id == result.Id);
    }

    [Fact]
    public async Task Handle_PrunedBytesSmallerThanNewVersion_Refused()
    {
        // Only 50 bytes are freed by pruning; the new version needs 200, so
        // net additional usage (150) still blows past the 100-byte limit.
        var (handler, _, file, tenantId, userId) = CreateSut(quotaLimit: 100, existingVersionSizeBytes: 50);
        var command = new CreateFileVersionCommand(tenantId, userId, file.Id, "v2", SizeBytes: 200, null, null);

        var act = () => handler.Handle(command, CancellationToken.None);

        await act.Should().ThrowAsync<QuotaExceededException>();
    }
}
