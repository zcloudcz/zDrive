using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Handler-level tests for the download-grant rules, run against EF Core
/// InMemory — no Docker needed. In particular
/// Handle_FileOutsideShare_ThrowsNotFound is the teeth check for the
/// ancestor/descendant containment check in PublicShareAccess.FindWithinShareAsync:
/// removing that check makes this test the one that catches it, since it is
/// the only place "a file id that exists but isn't under the shared root"
/// gets exercised without spinning up the full Testcontainers suite.
/// </summary>
[Trait("Category", "Unit")]
public sealed class CreateShareDownloadGrantCommandHandlerTests
{
    private const string TestKey = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="; // base64 of 32 'a' bytes

    private static (InMemoryFileDbContext Db, Guid TenantId, Guid OwnerId) SeedTree(
        out FileNode rootFolder, out FileNode nestedFile, out FileNode outsideFile, out FileNode noManifestFile)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();

        rootFolder = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "root", IsFolder = true };
        nestedFile = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "nested.txt",
            IsFolder = false, ParentId = rootFolder.Id, SizeBytes = 42, ManifestHash = new string('a', 64)
        };
        outsideFile = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "outside.txt",
            IsFolder = false, SizeBytes = 1, ManifestHash = new string('b', 64)
        };
        noManifestFile = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "not-uploaded.txt",
            IsFolder = false, ParentId = rootFolder.Id
        };

        db.FileNodes.AddRange(rootFolder, nestedFile, outsideFile, noManifestFile);

        var share = new Share
        {
            Id = Guid.NewGuid(),
            FileId = rootFolder.Id,
            SharedBy = ownerId,
            Permission = Permission.Read,
            LinkToken = "test-token"
        };
        db.Shares.Add(share);
        db.SaveChanges();

        return (db, tenantId, ownerId);
    }

    private static CreateShareDownloadGrantCommandHandler MakeHandler(InMemoryFileDbContext db, string? key = TestKey) =>
        new(db, Options.Create(new ShareDownloadGrantOptions { DownloadGrantKey = key }));

    [Fact]
    public async Task Handle_NestedFile_ReturnsGrantAddressedToOwner()
    {
        var (db, tenantId, ownerId) = SeedTree(out _, out var nestedFile, out _, out _);
        var handler = MakeHandler(db);

        var result = await handler.Handle(
            new CreateShareDownloadGrantCommand("test-token", nestedFile.Id), CancellationToken.None);

        result.FileId.Should().Be(nestedFile.Id);
        result.ManifestHash.Should().Be(nestedFile.ManifestHash);

        ShareDownloadGrant.TryValidate(result.Grant, Convert.FromBase64String(TestKey), DateTimeOffset.UtcNow, out var payload)
            .Should().BeTrue();
        payload.TenantId.Should().Be(tenantId);
        payload.OwnerUserId.Should().Be(ownerId);
        payload.FileId.Should().Be(nestedFile.Id);
        payload.ManifestHash.Should().Be(nestedFile.ManifestHash);
    }

    [Fact]
    public async Task Handle_RootIsAFile_ReturnsGrantForRoot()
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var rootFile = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "shared.txt",
            IsFolder = false, SizeBytes = 5, ManifestHash = new string('c', 64)
        };
        db.FileNodes.Add(rootFile);
        db.Shares.Add(new Share { Id = Guid.NewGuid(), FileId = rootFile.Id, SharedBy = ownerId, Permission = Permission.Read, LinkToken = "root-file-token" });
        await db.SaveChangesAsync();
        var handler = MakeHandler(db);

        var result = await handler.Handle(
            new CreateShareDownloadGrantCommand("root-file-token", rootFile.Id), CancellationToken.None);

        result.FileId.Should().Be(rootFile.Id);
    }

    [Fact]
    public async Task Handle_FileOutsideShare_ThrowsNotFound()
    {
        var (db, _, _) = SeedTree(out _, out _, out var outsideFile, out _);
        var handler = MakeHandler(db);

        var act = () => handler.Handle(new CreateShareDownloadGrantCommand("test-token", outsideFile.Id), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Handle_FolderId_ThrowsNotFound()
    {
        var (db, _, _) = SeedTree(out var rootFolder, out _, out _, out _);
        var handler = MakeHandler(db);

        var act = () => handler.Handle(new CreateShareDownloadGrantCommand("test-token", rootFolder.Id), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Handle_FileWithoutManifest_ThrowsNotFound()
    {
        var (db, _, _) = SeedTree(out _, out _, out _, out var noManifestFile);
        var handler = MakeHandler(db);

        var act = () => handler.Handle(new CreateShareDownloadGrantCommand("test-token", noManifestFile.Id), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Handle_KeyNotConfigured_ThrowsNotFound()
    {
        var (db, _, _) = SeedTree(out _, out var nestedFile, out _, out _);
        var handler = MakeHandler(db, key: null);

        var act = () => handler.Handle(new CreateShareDownloadGrantCommand("test-token", nestedFile.Id), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Handle_ShareExpiringSoon_CapsGrantExpiryToShareExpiry()
    {
        // The share expires well inside the 1h grant TTL — StorageService has
        // no way to see that the share expired, so the grant's own ExpiresAt
        // is the only thing that stops it outliving the share.
        var shareExpiresAt = DateTime.UtcNow.AddMinutes(10);
        var (db, file, handler) = SeedFileWithShareExpiry(shareExpiresAt);

        var result = await handler.Handle(new CreateShareDownloadGrantCommand("expiring-token", file.Id), CancellationToken.None);

        result.ExpiresAt.Should().BeCloseTo(new DateTimeOffset(shareExpiresAt, TimeSpan.Zero), TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Handle_ShareWithNoExpiry_UsesUncappedOneHourTtl()
    {
        var (db, file, handler) = SeedFileWithShareExpiry(shareExpiresAt: null);

        var result = await handler.Handle(new CreateShareDownloadGrantCommand("expiring-token", file.Id), CancellationToken.None);

        result.ExpiresAt.Should().BeCloseTo(DateTimeOffset.UtcNow.AddHours(1), TimeSpan.FromSeconds(5));
    }

    private static (InMemoryFileDbContext Db, FileNode File, CreateShareDownloadGrantCommandHandler Handler) SeedFileWithShareExpiry(
        DateTime? shareExpiresAt)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var file = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "expiring.txt",
            IsFolder = false, SizeBytes = 5, ManifestHash = new string('d', 64)
        };
        db.FileNodes.Add(file);
        db.Shares.Add(new Share
        {
            Id = Guid.NewGuid(),
            FileId = file.Id,
            SharedBy = ownerId,
            Permission = Permission.Read,
            LinkToken = "expiring-token",
            ExpiresAt = shareExpiresAt
        });
        db.SaveChanges();

        return (db, file, MakeHandler(db));
    }
}
