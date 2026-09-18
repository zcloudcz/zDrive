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
/// Quota enforcement at the one place both the authenticated and the
/// link-driven upload flow (package A) go through: recording a version.
/// </summary>
[Trait("Category", "Unit")]
public sealed class CreateFileVersionCommandHandlerTests
{
    private static (CreateFileVersionCommandHandler Handler, InMemoryFileDbContext Db, FileNode File, Guid TenantId, Guid UserId)
        CreateSut(long quotaLimit)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var file = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = userId, Name = "f.txt", IsFolder = false };
        db.FileNodes.Add(file);
        db.SaveChanges();

        var versioning = Options.Create(new VersioningOptions());
        var quota = new StorageQuota(db, Options.Create(new StorageOptions { DefaultUserQuotaBytes = quotaLimit }));
        var handler = new CreateFileVersionCommandHandler(db, versioning, quota);

        return (handler, db, file, tenantId, userId);
    }

    [Fact]
    public async Task Handle_AtTheLimit_ThrowsQuotaExceeded()
    {
        var (handler, _, file, tenantId, userId) = CreateSut(quotaLimit: 100);
        var command = new CreateFileVersionCommand(tenantId, userId, file.Id, "v1", SizeBytes: 101, null, null);

        var act = () => handler.Handle(command, CancellationToken.None);

        await act.Should().ThrowAsync<QuotaExceededException>();
    }

    [Fact]
    public async Task Handle_OneByteUnderLimit_RecordsVersion()
    {
        var (handler, db, file, tenantId, userId) = CreateSut(quotaLimit: 100);
        var command = new CreateFileVersionCommand(tenantId, userId, file.Id, "v1", SizeBytes: 100, null, null);

        var result = await handler.Handle(command, CancellationToken.None);

        result.SizeBytes.Should().Be(100);
        db.FileVersions.Should().ContainSingle(v => v.FileId == file.Id);
    }

    [Fact]
    public async Task Handle_ClaimLimit_OverridesConfigDefault()
    {
        var (handler, _, file, tenantId, userId) = CreateSut(quotaLimit: 100);
        // Config default (100) would refuse 150 bytes; the JWT claim raises it.
        var command = new CreateFileVersionCommand(tenantId, userId, file.Id, "v1", SizeBytes: 150, null, null, ClaimQuotaBytes: 200);

        var result = await handler.Handle(command, CancellationToken.None);

        result.SizeBytes.Should().Be(150);
    }
}
