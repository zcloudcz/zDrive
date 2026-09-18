using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.Queries.ListSharedChildren;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Handler-level tests for the shared-folder-listing rules, run against EF
/// Core InMemory instead of the Testcontainers Postgres fixture — no Docker
/// needed, so these still run when ShareFlowTests-style integration coverage
/// can't (see MEMORY.md / this PR's own report for what could not execute
/// here).
/// </summary>
[Trait("Category", "Unit")]
public sealed class ListSharedChildrenQueryHandlerTests
{
    private static (InMemoryFileDbContext Db, Guid TenantId, Guid OwnerId) SeedTree(out FileNode root, out FileNode nested, out FileNode nestedChild, out FileNode outside)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();

        root = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "root", IsFolder = true };
        nested = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "nested", IsFolder = true, ParentId = root.Id };
        nestedChild = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "leaf.txt", IsFolder = false, ParentId = nested.Id, SizeBytes = 10 };
        outside = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "outside", IsFolder = true };

        db.FileNodes.AddRange(root, nested, nestedChild, outside);

        var share = new Share
        {
            Id = Guid.NewGuid(),
            FileId = root.Id,
            SharedBy = ownerId,
            Permission = Permission.Read,
            LinkToken = "test-token"
        };
        db.Shares.Add(share);
        db.SaveChanges();

        return (db, tenantId, ownerId);
    }

    [Fact]
    public async Task Handle_RootFolder_ReturnsDirectChildren()
    {
        var (db, _, _) = SeedTree(out var root, out var nested, out _, out _);
        var handler = new ListSharedChildrenQueryHandler(db);

        var result = await handler.Handle(new ListSharedChildrenQuery("test-token", null), CancellationToken.None);

        result.Should().ContainSingle(f => f.Id == nested.Id);
    }

    [Fact]
    public async Task Handle_NestedSubfolder_ReturnsItsChildren()
    {
        var (db, _, _) = SeedTree(out _, out var nested, out var nestedChild, out _);
        var handler = new ListSharedChildrenQueryHandler(db);

        var result = await handler.Handle(new ListSharedChildrenQuery("test-token", nested.Id), CancellationToken.None);

        result.Should().ContainSingle(f => f.Id == nestedChild.Id);
    }

    [Fact]
    public async Task Handle_FolderOutsideShare_ThrowsNotFound()
    {
        var (db, _, _) = SeedTree(out _, out _, out _, out var outside);
        var handler = new ListSharedChildrenQueryHandler(db);

        var act = () => handler.Handle(new ListSharedChildrenQuery("test-token", outside.Id), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Handle_DeletedSubfolder_ThrowsNotFound()
    {
        var (db, _, _) = SeedTree(out _, out var nested, out _, out _);
        nested.IsDeleted = true;
        await db.SaveChangesAsync();
        var handler = new ListSharedChildrenQueryHandler(db);

        var act = () => handler.Handle(new ListSharedChildrenQuery("test-token", nested.Id), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }
}
