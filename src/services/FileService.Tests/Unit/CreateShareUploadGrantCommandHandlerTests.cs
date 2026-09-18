using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.FileService.Application;
using ZDrive.FileService.Application.Commands.CreateShareUploadGrant;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Handler-level tests for POST shares/link/{token}/upload-grant, wired
/// through the real MediatR pipeline (this handler re-sends CreateFileCommand
/// rather than forking file-creation logic — see the contract) against EF
/// Core InMemory, no Docker.
/// </summary>
[Trait("Category", "Unit")]
public sealed class CreateShareUploadGrantCommandHandlerTests
{
    private const string TestKey = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="; // base64 of 32 'a' bytes

    private sealed record Ctx(IServiceProvider Services, InMemoryFileDbContext Db, Guid TenantId, Guid OwnerId, FileNode Root);

    private static Ctx Build(bool folderRoot = true, Permission permission = Permission.Write, long quotaLimit = 1_000_000)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var root = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "root", IsFolder = folderRoot
        };
        db.FileNodes.Add(root);
        db.Shares.Add(new Share
        {
            Id = Guid.NewGuid(), FileId = root.Id, SharedBy = ownerId, Permission = permission, LinkToken = "token"
        });
        db.SaveChanges();

        var services = new ServiceCollection();
        services.AddApplication();
        services.AddSingleton<IFileDbContext>(db);
        services.Configure<ShareDownloadGrantOptions>(o => o.DownloadGrantKey = TestKey);
        services.Configure<StorageOptions>(o => o.DefaultUserQuotaBytes = quotaLimit);
        services.Configure<VersioningOptions>(o => { });

        return new Ctx(services.BuildServiceProvider(), db, tenantId, ownerId, root);
    }

    private static byte[] Key => Convert.FromBase64String(TestKey);

    [Fact]
    public async Task Handle_ReadOnlyLink_ThrowsForbidden()
    {
        var ctx = Build(permission: Permission.Read);
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var act = () => mediator.Send(new CreateShareUploadGrantCommand("token", null, "new.txt", 10, Overwrite: false));

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task Handle_NewFileInFolderRoot_CreatesPlaceholderAndReturnsGrant()
    {
        var ctx = Build();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var result = await mediator.Send(new CreateShareUploadGrantCommand("token", null, "new.txt", 100, Overwrite: false));

        result.FileName.Should().Be("new.txt");
        result.MaxBytes.Should().Be(100);
        ShareUploadGrant.TryValidate(result.Grant, Key, DateTimeOffset.UtcNow, out var payload).Should().BeTrue();
        payload.FileId.Should().Be(result.FileId);
        payload.OwnerUserId.Should().Be(ctx.OwnerId);
        payload.TenantId.Should().Be(ctx.TenantId);
        payload.MaxBytes.Should().Be(100);
    }

    [Fact]
    public async Task Handle_NameCollisionWithoutOverwrite_ThrowsConflict()
    {
        var ctx = Build();
        ctx.Db.FileNodes.Add(new FileNode
        {
            Id = Guid.NewGuid(), TenantId = ctx.TenantId, UserId = ctx.OwnerId, ParentId = ctx.Root.Id,
            Name = "existing.txt", IsFolder = false, SizeBytes = 1
        });
        await ctx.Db.SaveChangesAsync();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var act = () => mediator.Send(new CreateShareUploadGrantCommand("token", null, "existing.txt", 10, Overwrite: false));

        await act.Should().ThrowAsync<ConflictException>();
    }

    [Fact]
    public async Task Handle_NameCollisionWithOverwrite_ReusesExistingFileId()
    {
        var ctx = Build();
        var existing = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = ctx.TenantId, UserId = ctx.OwnerId, ParentId = ctx.Root.Id,
            Name = "existing.txt", IsFolder = false, SizeBytes = 1
        };
        ctx.Db.FileNodes.Add(existing);
        await ctx.Db.SaveChangesAsync();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var result = await mediator.Send(new CreateShareUploadGrantCommand("token", null, "existing.txt", 10, Overwrite: true));

        result.FileId.Should().Be(existing.Id);
    }

    [Fact]
    public async Task Handle_NameCollisionWithFolder_ThrowsConflict()
    {
        var ctx = Build();
        ctx.Db.FileNodes.Add(new FileNode
        {
            Id = Guid.NewGuid(), TenantId = ctx.TenantId, UserId = ctx.OwnerId, ParentId = ctx.Root.Id,
            Name = "sub", IsFolder = true
        });
        await ctx.Db.SaveChangesAsync();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var act = () => mediator.Send(new CreateShareUploadGrantCommand("token", null, "sub", 10, Overwrite: true));

        await act.Should().ThrowAsync<ConflictException>();
    }

    [Fact]
    public async Task Handle_RootIsSingleFile_OverwriteRequired()
    {
        var ctx = Build(folderRoot: false);
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var act = () => mediator.Send(new CreateShareUploadGrantCommand("token", null, null, 10, Overwrite: false));

        await act.Should().ThrowAsync<ConflictException>();
    }

    [Fact]
    public async Task Handle_RootIsSingleFile_OverwriteTrueTargetsRoot()
    {
        var ctx = Build(folderRoot: false);
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var result = await mediator.Send(new CreateShareUploadGrantCommand("token", null, null, 10, Overwrite: true));

        result.FileId.Should().Be(ctx.Root.Id);
    }

    [Fact]
    public async Task Handle_QuotaExceeded_ThrowsQuotaExceeded()
    {
        var ctx = Build(quotaLimit: 5);
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();

        var act = () => mediator.Send(new CreateShareUploadGrantCommand("token", null, "big.bin", 1000, Overwrite: false));

        await act.Should().ThrowAsync<QuotaExceededException>();
    }
}
