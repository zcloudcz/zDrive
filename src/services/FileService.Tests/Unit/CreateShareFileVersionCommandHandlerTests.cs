using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.FileService.Application;
using ZDrive.FileService.Application.Commands.CreateShareFileVersion;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Handler-level tests for POST shares/link/{token}/files/{fileId}/versions.
/// Handle_ReplayedReceipt_DoesNotCreateSecondVersion is the teeth check for
/// idempotency: taking size/hash from the caller instead of the receipt, or
/// dropping the fileId match, breaks a different test
/// (Handle_ReceiptForDifferentFile_ThrowsNotFound) — see the report.
/// </summary>
[Trait("Category", "Unit")]
public sealed class CreateShareFileVersionCommandHandlerTests
{
    private const string TestKey = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=";
    private static byte[] Key => Convert.FromBase64String(TestKey);

    private sealed record Ctx(IServiceProvider Services, InMemoryFileDbContext Db, FileNode File);

    private static Ctx Build()
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var file = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = ownerId, Name = "doc.txt",
            IsFolder = false, SizeBytes = 5, ManifestHash = new string('a', 64)
        };
        db.FileNodes.Add(file);
        db.Shares.Add(new Share { Id = Guid.NewGuid(), FileId = file.Id, SharedBy = ownerId, Permission = Permission.Write, LinkToken = "token" });
        db.SaveChanges();

        var services = new ServiceCollection();
        services.AddApplication();
        services.AddSingleton<IFileDbContext>(db);
        services.Configure<ShareDownloadGrantOptions>(o => o.DownloadGrantKey = TestKey);
        services.Configure<StorageOptions>(o => { });
        services.Configure<VersioningOptions>(o => { });

        return new Ctx(services.BuildServiceProvider(), db, file);
    }

    private static string MakeReceipt(Guid fileId, string manifestHash, long sizeBytes) =>
        ShareUploadReceipt.Create(new ShareUploadReceipt.Payload(fileId, manifestHash, sizeBytes, DateTimeOffset.UtcNow.AddMinutes(15)), Key);

    [Fact]
    public async Task Handle_NewManifestHash_RecordsVersionAndUpdatesFile()
    {
        var ctx = Build();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();
        var receipt = MakeReceipt(ctx.File.Id, new string('b', 64), 99);

        var result = await mediator.Send(new CreateShareFileVersionCommand("token", ctx.File.Id, receipt));

        result.ManifestHash.Should().Be(new string('b', 64));
        result.SizeBytes.Should().Be(99);
    }

    [Fact]
    public async Task Handle_ReplayedReceipt_DoesNotCreateSecondVersion()
    {
        var ctx = Build();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();
        var receipt = MakeReceipt(ctx.File.Id, new string('b', 64), 99);

        await mediator.Send(new CreateShareFileVersionCommand("token", ctx.File.Id, receipt));
        await mediator.Send(new CreateShareFileVersionCommand("token", ctx.File.Id, receipt));

        ctx.Db.FileVersions.Count(v => v.FileId == ctx.File.Id && v.ManifestHash == new string('b', 64)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_ReceiptForDifferentFile_ThrowsNotFound()
    {
        var ctx = Build();
        var mediator = ctx.Services.GetRequiredService<MediatR.IMediator>();
        var receiptForOtherFile = MakeReceipt(Guid.NewGuid(), new string('b', 64), 99);

        var act = () => mediator.Send(new CreateShareFileVersionCommand("token", ctx.File.Id, receiptForOtherFile));

        await act.Should().ThrowAsync<NotFoundException>();
    }
}
