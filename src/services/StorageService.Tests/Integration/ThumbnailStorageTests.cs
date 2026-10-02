using FluentAssertions;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.Commands.DeleteThumbnails;
using ZDrive.StorageService.Application.Commands.PutThumbnail;
using ZDrive.StorageService.Application.Queries.GetThumbnail;

namespace ZDrive.StorageService.Tests.Integration;

/// <summary>
/// Thumbnails are written and read in-process by the photo module (there is no
/// HTTP endpoint), so these go through MediatR against real Azurite.
/// </summary>
[Trait("Category", "Integration")]
public sealed class ThumbnailStorageTests : IClassFixture<StorageServiceFactory>
{
    private readonly StorageServiceFactory _factory;

    public ThumbnailStorageTests(StorageServiceFactory factory) => _factory = factory;

    [Fact]
    public async Task PutThumbnail_ThenGet_ReturnsSameBytes()
    {
        var (tenantId, userId, photoId) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var bytes = new byte[300];
        Random.Shared.NextBytes(bytes);

        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        await mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, "v1", 256, bytes));

        await using var stream = await mediator.Send(new GetThumbnailQuery(tenantId, userId, photoId, "v1", 256));
        using var copy = new MemoryStream();
        await stream.CopyToAsync(copy);
        copy.ToArray().Should().Equal(bytes);
    }

    [Fact]
    public async Task PutThumbnail_Twice_OverwritesPreviousContent()
    {
        var (tenantId, userId, photoId) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();

        await mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, "v1", 1024, [1, 2, 3]));
        await mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, "v1", 1024, [9, 9]));

        await using var stream = await mediator.Send(new GetThumbnailQuery(tenantId, userId, photoId, "v1", 1024));
        using var copy = new MemoryStream();
        await stream.CopyToAsync(copy);
        copy.ToArray().Should().Equal(9, 9);
    }

    [Fact]
    public async Task GetThumbnail_Missing_ThrowsNotFound()
    {
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();

        var act = async () => await mediator.Send(new GetThumbnailQuery(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "v1", 256));

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task GetThumbnail_OtherUsersPrefix_ThrowsNotFound()
    {
        // The blob path embeds tenant and user, so another owner cannot address it.
        var (tenantId, userId, photoId) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        await mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, "v1", 256, [1]));

        var act = async () => await mediator.Send(new GetThumbnailQuery(tenantId, Guid.NewGuid(), photoId, "v1", 256));

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Thumbnails_DifferentVersions_AreIndependentAndDeleteRemovesAll()
    {
        var (tenantId, userId, photoId) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        await mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, "aaaa", 256, [1]));
        await mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, "bbbb", 256, [2]));

        await using (var a = await mediator.Send(new GetThumbnailQuery(tenantId, userId, photoId, "aaaa", 256)))
            a.ReadByte().Should().Be(1);
        await using (var b = await mediator.Send(new GetThumbnailQuery(tenantId, userId, photoId, "bbbb", 256)))
            b.ReadByte().Should().Be(2);

        await mediator.Send(new DeleteThumbnailsCommand(tenantId, userId, photoId));

        foreach (var version in new[] { "aaaa", "bbbb" })
        {
            var act = async () => await mediator.Send(new GetThumbnailQuery(tenantId, userId, photoId, version, 256));
            await act.Should().ThrowAsync<NotFoundException>();
        }
    }

    [Fact]
    public async Task PutThumbnail_VersionThatIsNotAPlainToken_FailsValidation()
    {
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();

        var act = async () => await mediator.Send(new PutThumbnailCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "../evil", 256, [1]));

        await act.Should().ThrowAsync<FluentValidation.ValidationException>("the version becomes a blob path segment");
    }
}
