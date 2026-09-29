using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SkiaSharp;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Domain.Entities;
using ZDrive.PhotoService.Application.Common;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.PhotoService.Domain.Enums;
using ZDrive.PhotoService.Infrastructure.Ingest;
using ZDrive.PhotoService.Infrastructure.Persistence;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.PhotoService.Tests.Integration;

/// <summary>
/// End to end: upload through the real File + Storage APIs (Postgres +
/// Azurite), let the ingest pump process the change feed, read the result
/// through the Photo API. Every test uses its own user so timelines are isolated.
/// </summary>
[Trait("Category", "Integration")]
public sealed class PhotoIngestFlowTests : IClassFixture<PhotoServiceFactory>
{
    private readonly PhotoServiceFactory _factory;

    public PhotoIngestFlowTests(PhotoServiceFactory factory) => _factory = factory;

    private (HttpClient Client, Guid UserId, Guid TenantId) NewUser()
    {
        var userId = Guid.NewGuid();
        var tenantId = Guid.NewGuid();
        return (_factory.CreateAuthenticatedClient(userId, tenantId), userId, tenantId);
    }

    [Fact]
    public async Task IngestFlow_JpegWithExif_TimelineHasTakenAtAndGps_ThumbnailIsWebPOfExpectedSize()
    {
        var (client, _, _) = NewUser();
        // Stored 400x200 with EXIF orientation 6 (rotate 90 cw): displays as 200x400.
        var jpeg = TestImages.Jpeg(400, 200, new(
            Orientation: 6,
            DateTimeOriginal: "2021:07:04 12:34:56",
            OffsetTimeOriginal: "+02:00",
            Gps: (50.0917, 14.42),
            Make: "Acme",
            Model: "Cam1"));

        var file = await UploadImageAsync(client, "holiday.jpg", jpeg);
        await _factory.DrainIngestAsync();

        var photo = await FindInTimelineAsync(client, file.Id);
        photo.Should().NotBeNull("the worker turned the upload into a processed photo");
        photo!.TakenAt.Should().Be(new DateTime(2021, 7, 4, 10, 34, 56, DateTimeKind.Utc), "+02:00 offset is honoured");
        photo.Lat.Should().BeApproximately(50.0917, 0.001);
        photo.Lng.Should().BeApproximately(14.42, 0.001);
        photo.CameraMake.Should().Be("Acme");
        photo.CameraModel.Should().Be("Cam1");
        photo.Orientation.Should().Be(6);
        (photo.Width, photo.Height).Should().Be((200, 400), "dimensions are as displayed, after orientation");
        photo.ProcessingStatus.Should().Be("Processed");
        photo.ThumbnailsReady.Should().BeTrue();

        var small = await client.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/256");
        small.StatusCode.Should().Be(HttpStatusCode.OK);
        small.Content.Headers.ContentType!.MediaType.Should().Be("image/webp");
        small.Headers.CacheControl!.Private.Should().BeTrue();
        small.Headers.CacheControl.MaxAge.Should().Be(TimeSpan.FromHours(1));
        small.Headers.ETag.Should().NotBeNull();
        DecodedSize(await small.Content.ReadAsByteArrayAsync()).Should().Be((128, 256));

        var large = await client.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/1024");
        large.StatusCode.Should().Be(HttpStatusCode.OK);
        DecodedSize(await large.Content.ReadAsByteArrayAsync()).Should().Be((200, 400), "originals are never upscaled");

        var notModified = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/photos/{photo.Id}/thumbnail/256");
        notModified.Headers.TryAddWithoutValidation("If-None-Match", small.Headers.ETag!.ToString());
        (await client.SendAsync(notModified)).StatusCode.Should().Be(HttpStatusCode.NotModified);
    }

    [Fact]
    public async Task IngestFlow_ImageWithoutExif_FallsBackToFileNameDate()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "IMG_20231225_143022.png", TestImages.Png(64, 32), "image/png");

        await _factory.DrainIngestAsync();

        var photo = await FindInTimelineAsync(client, file.Id);
        photo!.TakenAt.Should().Be(new DateTime(2023, 12, 25, 14, 30, 22, DateTimeKind.Utc));
        photo.Lat.Should().BeNull();
    }

    [Fact]
    public async Task IngestFlow_FileTrashed_DisappearsFromTimeline_RestoredReturns()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "trash-me.jpg", TestImages.Jpeg(120, 80));
        await _factory.DrainIngestAsync();
        var photo = (await FindInTimelineAsync(client, file.Id))!;

        (await client.DeleteAsync($"/api/v1/files/{file.Id}")).StatusCode.Should().Be(HttpStatusCode.OK);
        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, file.Id)).Should().BeNull();
        (await client.GetAsync($"/api/v1/photos/{photo.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await client.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/256")).StatusCode.Should().Be(HttpStatusCode.NotFound);

        (await client.PostAsync($"/api/v1/files/{file.Id}/restore", null)).StatusCode.Should().Be(HttpStatusCode.OK);
        await _factory.DrainIngestAsync();

        var restored = await FindInTimelineAsync(client, file.Id);
        restored!.Id.Should().Be(photo.Id, "restore un-hides the same photo instead of creating another");
        (await client.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/256")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task IngestFlow_FolderTrashed_HidesPhotosInside()
    {
        var (client, _, _) = NewUser();
        var folder = await CreateNodeAsync(client, new { name = "Trip", isFolder = true });
        var file = await UploadImageAsync(client, "in-folder.jpg", TestImages.Jpeg(90, 60), parentId: folder.Id);
        await _factory.DrainIngestAsync();
        (await FindInTimelineAsync(client, file.Id)).Should().NotBeNull();

        await client.DeleteAsync($"/api/v1/files/{folder.Id}");
        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, file.Id)).Should().BeNull();
    }

    [Fact]
    public async Task IngestFlow_NewVersion_RegeneratesThumbnails()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "edited.jpg", TestImages.Jpeg(400, 200));
        await _factory.DrainIngestAsync();
        var first = (await FindInTimelineAsync(client, file.Id))!;
        var firstThumb = await client.GetAsync($"/api/v1/photos/{first.Id}/thumbnail/256");
        DecodedSize(await firstThumb.Content.ReadAsByteArrayAsync()).Should().Be((256, 128));

        // Same file, new content and a new size.
        await UploadVersionAsync(client, file.Id, TestImages.Jpeg(200, 300));
        await _factory.DrainIngestAsync();

        var second = (await FindInTimelineAsync(client, file.Id))!;
        second.Id.Should().Be(first.Id);
        (second.Width, second.Height).Should().Be((200, 300));
        var secondThumb = await client.GetAsync($"/api/v1/photos/{first.Id}/thumbnail/256");
        DecodedSize(await secondThumb.Content.ReadAsByteArrayAsync()).Should().Be((171, 256));
        secondThumb.Headers.ETag.Should().NotBe(firstThumb.Headers.ETag, "a new version must not revalidate as unchanged");
    }

    [Fact]
    public async Task IngestFlow_SameVersionSeenAgain_IsNotReprocessed()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "steady.jpg", TestImages.Jpeg(100, 100));
        await _factory.DrainIngestAsync();
        var processedAt = (await _factory.FindPhotoByFileAsync(file.Id))!.ProcessedAt;

        // A rename produces another change row for the same file and manifest.
        await client.PutAsJsonAsync($"/api/v1/files/{file.Id}/rename", new { newName = "steady-renamed.jpg" });
        await _factory.DrainIngestAsync();

        var photo = (await _factory.FindPhotoByFileAsync(file.Id))!;
        photo.ProcessedAt.Should().Be(processedAt, "the idempotency key (FileId, manifestHash) did not change");
        photo.OriginalFileName.Should().Be("steady-renamed.jpg");
    }

    [Fact]
    public async Task IngestFlow_CorruptImage_MarkedFailedAndWorkerContinues()
    {
        var (client, _, _) = NewUser();
        var corrupt = await UploadImageAsync(client, "broken.jpg", [.. "definitely not a jpeg"u8.ToArray(), .. new byte[64]]);
        var good = await UploadImageAsync(client, "fine.jpg", TestImages.Jpeg(80, 60));

        await _factory.DrainIngestAsync();

        var failed = (await _factory.FindPhotoByFileAsync(corrupt.Id))!;
        failed.ProcessingStatus.Should().Be(ProcessingStatus.Failed);
        failed.FailureReason.Should().NotBeNullOrWhiteSpace();
        failed.Attempts.Should().Be(1, "undecodable data is not retried");
        (await FindInTimelineAsync(client, corrupt.Id)).Should().BeNull("failed photos stay off the timeline");
        (await FindInTimelineAsync(client, good.Id)).Should().NotBeNull("one bad image must not stop the worker");
    }

    [Fact]
    public async Task IngestFlow_HeicFile_ProcessedWithoutThumbnails()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "iphone.heic", TestImages.HeicHeaderOnly(), "image/heic");

        await _factory.DrainIngestAsync();

        var photo = await FindInTimelineAsync(client, file.Id);
        photo.Should().NotBeNull("HEIC counts as Processed so the client can show a placeholder");
        photo!.ThumbnailsReady.Should().BeFalse();
        (await client.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/256")).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task IngestFlow_NonImageFile_CreatesNoPhoto()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "notes.txt", "hello"u8.ToArray(), "text/plain");

        await _factory.DrainIngestAsync();

        (await _factory.FindPhotoByFileAsync(file.Id)).Should().BeNull();
    }

    [Fact]
    public async Task IngestFlow_ImageRenamedToNonImage_HidesPhoto()
    {
        var (client, _, _) = NewUser();
        // No MIME type from the client, so the extension decides (MIME wins when present).
        var file = await UploadImageAsync(client, "pretend.jpg", TestImages.Jpeg(50, 50), "application/octet-stream");
        await _factory.DrainIngestAsync();

        await client.PutAsJsonAsync($"/api/v1/files/{file.Id}/rename", new { newName = "pretend.txt" });
        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, file.Id)).Should().BeNull();
        (await _factory.FindPhotoByFileAsync(file.Id))!.IsHidden.Should().BeTrue();
    }

    [Fact]
    public async Task IngestFlow_TransientStorageFailure_RetriesWithBackoffThenSucceeds()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "flaky.jpg", TestImages.Jpeg(100, 60));

        _factory.FailThumbnailWrites = true;
        try { await _factory.DrainIngestAsync(); }
        finally { _factory.FailThumbnailWrites = false; }

        var pending = (await _factory.FindPhotoByFileAsync(file.Id))!;
        pending.ProcessingStatus.Should().Be(ProcessingStatus.Ingested);
        pending.Attempts.Should().Be(1);
        pending.NextAttemptAt.Should().BeAfter(DateTime.UtcNow, "retry is backed off, not immediate");
        (await FindInTimelineAsync(client, file.Id)).Should().BeNull();

        await ExpireBackoffAsync(file.Id);
        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, file.Id)).Should().NotBeNull();
    }

    [Fact]
    public async Task IngestFlow_RepeatedTransientFailures_EndInFailedAfterThreeAttempts()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "hopeless.jpg", TestImages.Jpeg(100, 60));

        _factory.FailThumbnailWrites = true;
        try
        {
            for (var attempt = 0; attempt < 3; attempt++)
            {
                await _factory.DrainIngestAsync();
                await ExpireBackoffAsync(file.Id);
            }
        }
        finally { _factory.FailThumbnailWrites = false; }

        var photo = (await _factory.FindPhotoByFileAsync(file.Id))!;
        photo.ProcessingStatus.Should().Be(ProcessingStatus.Failed);
        photo.Attempts.Should().Be(3);
        photo.FailureReason.Should().Contain("Simulated");
    }

    [Fact]
    public async Task IngestPump_LowerIdCommitsLate_NotSkipped()
    {
        // ADR 0001 pattern: a change row with a LOWER id is still uncommitted
        // while a HIGHER id has committed and aged past the hold-back. A
        // reader that advanced past the higher id would lose the lower one
        // forever; the pump must wait on the SHARE lock instead.
        var (client, userId, tenantId) = NewUser();
        await _factory.DrainIngestAsync(); // clear earlier tests' backlog

        // Original of the late file is uploaded; its FileNode is not committed yet.
        var lateFileId = Guid.NewGuid();
        var lateHash = await UploadBlobAsync(client, lateFileId, "late.jpg", TestImages.Jpeg(60, 40));

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        using var writerScope = _factory.Services.CreateScope();
        var writer = writerScope.ServiceProvider.GetRequiredService<FileDbContext>();
        await using var transaction = await writer.Database.BeginTransactionAsync(timeout.Token);
        writer.FileNodes.Add(new FileNode
        {
            Id = lateFileId,
            UserId = userId,
            TenantId = tenantId,
            Name = "late.jpg",
            MimeType = "image/jpeg",
            SizeBytes = 1,
            ManifestHash = lateHash,
        });
        await writer.SaveChangesAsync(timeout.Token);
        await writer.Database.ExecuteSqlRawAsync(
            "UPDATE files.file_changes SET occurred_at = occurred_at - interval '10 seconds' WHERE id = (SELECT max(id) FROM files.file_changes)",
            timeout.Token);

        // The higher id commits normally and ages past the hold-back.
        var early = await UploadImageAsync(client, "early.jpg", TestImages.Jpeg(60, 40));
        await _factory.AgeChangesAsync();

        var pump = _factory.Services.GetRequiredService<PhotoIngestPump>();
        var reconcile = pump.ReconcileOnceAsync(timeout.Token);
        await WaitForBlockedFeedReadAsync(reconcile, timeout.Token);
        reconcile.IsCompleted.Should().BeFalse("an open lower-id insert must stop the cursor from advancing");

        await transaction.CommitAsync(timeout.Token);
        await reconcile;
        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, lateFileId)).Should().NotBeNull("the late commit must not be skipped");
        (await FindInTimelineAsync(client, early.Id)).Should().NotBeNull();
    }

    [Fact]
    public async Task IngestPump_CursorIsDurable_SecondReconcileStartsWhereFirstStopped()
    {
        var (client, _, _) = NewUser();
        await UploadImageAsync(client, "cursor.jpg", TestImages.Jpeg(30, 30));
        await _factory.DrainIngestAsync();

        var before = await ReadCursorAsync();
        before.Should().BeGreaterThan(0);

        var pump = _factory.Services.GetRequiredService<PhotoIngestPump>();
        (await pump.ReconcileOnceAsync(CancellationToken.None)).Should().BeFalse();
        (await ReadCursorAsync()).Should().Be(before, "nothing new since the persisted position");
    }

    [Fact]
    public async Task IngestFlow_ThumbnailsDoNotCountTowardQuota()
    {
        var (client, _, _) = NewUser();
        await UploadImageAsync(client, "quota.jpg", TestImages.Jpeg(300, 200));
        var before = await GetUsedBytesAsync(client);

        await _factory.DrainIngestAsync();

        before.Should().BeGreaterThan(0);
        (await GetUsedBytesAsync(client)).Should().Be(before);
    }

    [Fact]
    public async Task GetThumbnail_PhotoOfAnotherUser_Returns404()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "private.jpg", TestImages.Jpeg(60, 40));
        await _factory.DrainIngestAsync();
        var photo = (await FindInTimelineAsync(client, file.Id))!;

        using var stranger = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        (await stranger.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/256")).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetThumbnail_UnsupportedSize_Returns400()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "size.jpg", TestImages.Jpeg(60, 40));
        await _factory.DrainIngestAsync();
        var photo = (await FindInTimelineAsync(client, file.Id))!;

        (await client.GetAsync($"/api/v1/photos/{photo.Id}/thumbnail/512")).StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GetThumbnail_WithoutToken_Returns401()
    {
        using var anonymous = _factory.CreateClient();
        (await anonymous.GetAsync($"/api/v1/photos/{Guid.NewGuid()}/thumbnail/256")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task IngestFlow_DecompressionBombPng_FailsPermanentlyAndWorkerContinues()
    {
        var (client, _, _) = NewUser();
        var bomb = await UploadImageAsync(client, "bomb.png", TestImages.PngDeclaring(20_000, 20_000), "image/png");
        var good = await UploadImageAsync(client, "after-bomb.jpg", TestImages.Jpeg(80, 60));

        await _factory.DrainIngestAsync();

        var failed = (await _factory.FindPhotoByFileAsync(bomb.Id))!;
        failed.ProcessingStatus.Should().Be(ProcessingStatus.Failed);
        failed.FailureReason.Should().StartWith("TooManyPixels");
        failed.Attempts.Should().Be(1, "a declared size cannot get smaller on retry");
        (await FindInTimelineAsync(client, good.Id)).Should().NotBeNull();
    }

    [Fact]
    public async Task IngestFlow_LateWorkerForOlderVersion_DoesNotOverwriteNewerThumbnails()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "race.jpg", TestImages.Jpeg(400, 200));
        await _factory.AgeChangesAsync();
        var pump = _factory.Services.GetRequiredService<PhotoIngestPump>();
        await pump.ReconcileOnceAsync(CancellationToken.None);
        var hashA = (await _factory.FindPhotoByFileAsync(file.Id))!.SourceManifestHash!;

        // Worker A claims version A and stalls right before writing its thumbnails.
        var reachedA = new TaskCompletionSource();
        var releaseA = new TaskCompletionSource();
        var stalled = false;
        _factory.BeforeThumbnailWrite = async version =>
        {
            if (version != ThumbnailVersion.Of(hashA) || stalled) return;
            stalled = true;
            reachedA.SetResult();
            await releaseA.Task;
        };

        try
        {
            var workerA = pump.ProcessPendingAsync(CancellationToken.None);
            await reachedA.Task.WaitAsync(TimeSpan.FromSeconds(30));

            // Meanwhile version B arrives and is fully processed.
            await UploadVersionAsync(client, file.Id, TestImages.Jpeg(200, 300));
            await _factory.AgeChangesAsync();
            await pump.ReconcileOnceAsync(CancellationToken.None);
            await pump.ProcessPendingAsync(CancellationToken.None);
            var afterB = (await _factory.FindPhotoByFileAsync(file.Id))!;
            afterB.ProcessedManifestHash.Should().NotBe(hashA).And.NotBeNull();

            // Now the stale worker finishes.
            releaseA.SetResult();
            await workerA;

            var final = (await _factory.FindPhotoByFileAsync(file.Id))!;
            final.ProcessedManifestHash.Should().Be(afterB.ProcessedManifestHash, "the conditional update of the stale worker must be a no-op");
            (final.Width, final.Height).Should().Be((200, 300));
            var thumb = await client.GetAsync($"/api/v1/photos/{final.Id}/thumbnail/256");
            thumb.StatusCode.Should().Be(HttpStatusCode.OK);
            DecodedSize(await thumb.Content.ReadAsByteArrayAsync()).Should().Be((171, 256), "still version B's bytes");
        }
        finally
        {
            _factory.BeforeThumbnailWrite = null;
            releaseA.TrySetResult();
        }
    }

    [Fact]
    public async Task IngestFlow_FileWithNoChangeRow_IsPickedUpByBootstrapAndLaterChangesAreFollowed()
    {
        var (client, _, _) = NewUser();
        await UploadImageAsync(client, "anchor.jpg", TestImages.Jpeg(20, 20)); // keeps a row in the log, so the head is > 0
        var preexisting = await UploadImageAsync(client, "from-before-the-log.jpg", TestImages.Jpeg(90, 60));
        await _factory.AgeChangesAsync();
        // ADR 0001: the log started empty, so files that predate it have no rows at all.
        await ExecuteFileSqlAsync($"""DELETE FROM files.file_changes WHERE file_id = '{preexisting.Id}'""");
        await ResetCursorAsync(); // fresh cursor row => bootstrap

        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, preexisting.Id)).Should().NotBeNull("bootstrap scans current node state");
        var cursor = await ReadCursorRowAsync();
        cursor.BootstrapCompletedAt.Should().NotBeNull();
        cursor.LastChangeId.Should().BeGreaterThan(0, "the cursor moved to the feed head captured before the scan");

        var later = await UploadImageAsync(client, "after-bootstrap.jpg", TestImages.Jpeg(50, 50));
        await _factory.DrainIngestAsync();
        (await FindInTimelineAsync(client, later.Id)).Should().NotBeNull("after the bootstrap the change feed takes over");
    }

    [Fact]
    public async Task IngestFlow_BootstrapInterrupted_ResumesFromPersistedPosition()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "resume.jpg", TestImages.Jpeg(40, 40));
        await _factory.AgeChangesAsync();
        await ExecuteFileSqlAsync($"""DELETE FROM files.file_changes WHERE file_id = '{file.Id}'""");
        await ResetCursorAsync();

        // Simulate a crash after the head was captured but before the scan finished.
        await ExecutePhotoSqlAsync(
            """INSERT INTO photos.ingest_cursors ("Name","LastChangeId","UpdatedAt","BootstrapHead") VALUES ('file-changes',0,now(),0)""");

        await _factory.DrainIngestAsync();

        (await FindInTimelineAsync(client, file.Id)).Should().NotBeNull();
        (await ReadCursorRowAsync()).BootstrapCompletedAt.Should().NotBeNull();
    }

    [Fact]
    public async Task IngestFlow_NewVersionQueued_KeepsShowingLastGoodVersionUntilProcessed()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "keep-visible.jpg", TestImages.Jpeg(400, 200));
        await _factory.DrainIngestAsync();
        var first = (await FindInTimelineAsync(client, file.Id))!;

        await UploadVersionAsync(client, file.Id, TestImages.Jpeg(200, 300));
        await _factory.AgeChangesAsync();
        var pump = _factory.Services.GetRequiredService<PhotoIngestPump>();
        await pump.ReconcileOnceAsync(CancellationToken.None); // queued, NOT processed

        var queued = (await _factory.FindPhotoByFileAsync(file.Id))!;
        queued.SourceManifestHash.Should().NotBe(queued.ProcessedManifestHash, "the new version waits");
        queued.ProcessingStatus.Should().Be(ProcessingStatus.Processed, "an already-processed photo is not demoted while reprocessing");
        var stillThere = await FindInTimelineAsync(client, file.Id);
        stillThere.Should().NotBeNull("it must not vanish from the timeline");
        (stillThere!.Width, stillThere.Height).Should().Be((first.Width, first.Height));
        var oldThumb = await client.GetAsync($"/api/v1/photos/{first.Id}/thumbnail/256");
        DecodedSize(await oldThumb.Content.ReadAsByteArrayAsync()).Should().Be((256, 128), "the previous version's thumbnails are still served");

        await pump.ProcessPendingAsync(CancellationToken.None);

        var done = (await FindInTimelineAsync(client, file.Id))!;
        (done.Width, done.Height).Should().Be((200, 300));
    }

    [Fact]
    public async Task IngestFlow_NewVersionCorrupt_KeepsLastGoodVersionAndRecordsTheFailure()
    {
        var (client, _, _) = NewUser();
        var file = await UploadImageAsync(client, "good-then-bad.jpg", TestImages.Jpeg(400, 200));
        await _factory.DrainIngestAsync();
        var good = (await _factory.FindPhotoByFileAsync(file.Id))!;

        await UploadVersionAsync(client, file.Id, [.. "not an image any more"u8.ToArray(), .. new byte[40]]);
        await _factory.DrainIngestAsync();

        var after = (await _factory.FindPhotoByFileAsync(file.Id))!;
        after.ProcessingStatus.Should().Be(ProcessingStatus.Processed, "a good version exists, so the photo is not flipped to Failed");
        after.ProcessedManifestHash.Should().Be(good.ProcessedManifestHash);
        after.FailureReason.Should().NotBeNullOrWhiteSpace();
        (await FindInTimelineAsync(client, file.Id))!.Width.Should().Be(400);
        DecodedSize(await (await client.GetAsync($"/api/v1/photos/{good.Id}/thumbnail/256")).Content.ReadAsByteArrayAsync())
            .Should().Be((256, 128));

        var attempts = after.Attempts;
        await _factory.DrainIngestAsync();
        (await _factory.FindPhotoByFileAsync(file.Id))!.Attempts.Should().Be(attempts, "a version that gave up is not claimed again");
    }

    [Fact]
    public async Task IngestFlow_FilePurgedFromTrash_DeletesPhotoRowAndItsThumbnails()
    {
        var (client, userId, tenantId) = NewUser();
        var file = await UploadImageAsync(client, "purge-me.jpg", TestImages.Jpeg(100, 80));
        await _factory.DrainIngestAsync();
        var photo = (await _factory.FindPhotoByFileAsync(file.Id))!;
        using (var scope = _factory.Services.CreateScope())
        {
            var store = scope.ServiceProvider.GetRequiredService<IThumbnailStore>();
            (await store.OpenAsync(tenantId, userId, photo.Id, ThumbnailVersion.Of(photo.ProcessedManifestHash!), 256, default))
                .Should().NotBeNull();
        }

        await client.DeleteAsync($"/api/v1/files/{file.Id}");
        (await client.DeleteAsync("/api/v1/files/trash")).StatusCode.Should().Be(HttpStatusCode.OK); // hard delete: node gone
        await _factory.DrainIngestAsync();

        (await _factory.FindPhotoByFileAsync(file.Id)).Should().BeNull("a purged file can never come back, so the row goes too");
        using (var scope = _factory.Services.CreateScope())
        {
            var store = scope.ServiceProvider.GetRequiredService<IThumbnailStore>();
            (await store.OpenAsync(tenantId, userId, photo.Id, ThumbnailVersion.Of(photo.ProcessedManifestHash!), 256, default))
                .Should().BeNull();
        }
    }

    [Fact]
    public async Task IngestPump_NothingQueued_ProcessNextReportsIdle()
    {
        await _factory.DrainIngestAsync();

        (await _factory.Services.GetRequiredService<PhotoIngestPump>().ProcessNextAsync(CancellationToken.None)).Should().BeFalse();
    }

    // ---------------------------------------------------------------- helpers

    private static (int Width, int Height) DecodedSize(byte[] webp)
    {
        using var bitmap = SKBitmap.Decode(webp);
        bitmap.Should().NotBeNull("the thumbnail must be a decodable image");
        return (bitmap.Width, bitmap.Height);
    }

    private static async Task<PhotoDto?> FindInTimelineAsync(HttpClient client, Guid fileId)
    {
        var response = await client.GetAsync("/api/v1/photos/timeline?limit=200");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var timeline = await response.Content.ReadFromJsonAsync<TimelineResultDto>();
        return timeline!.Photos.FirstOrDefault(p => p.FileId == fileId);
    }

    private static async Task<FileDto> CreateNodeAsync(HttpClient client, object body)
    {
        var response = await client.PostAsJsonAsync("/api/v1/files", body);
        response.StatusCode.Should().Be(HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    /// <summary>Creates the file node, uploads the content in two chunks and records the version.</summary>
    private static async Task<FileDto> UploadImageAsync(
        HttpClient client, string name, byte[] content, string mime = "image/jpeg", Guid? parentId = null)
    {
        var file = await CreateNodeAsync(client, new { name, isFolder = false, parentId, mimeType = mime });
        await UploadVersionAsync(client, file.Id, content, name);
        return file;
    }

    private static async Task UploadVersionAsync(HttpClient client, Guid fileId, byte[] content, string name = "file")
    {
        var hash = await UploadBlobAsync(client, fileId, name, content);
        var response = await client.PostAsJsonAsync($"/api/v1/files/{fileId}/versions", new
        {
            blobVersionId = hash,
            sizeBytes = content.Length,
            manifestHash = hash,
            comment = (string?)null,
        });
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
    }

    /// <summary>Storage half of an upload (two chunks, so chunk assembly is exercised). Returns the manifest hash.</summary>
    private static async Task<string> UploadBlobAsync(HttpClient client, Guid fileId, string name, byte[] content)
    {
        var half = Math.Max(1, content.Length / 2);
        byte[][] chunks = content.Length > 1 ? [content[..half], content[half..]] : [content];

        var init = await client.PostAsJsonAsync("/api/v1/storage/upload/init", new { fileId, fileName = name, totalChunks = chunks.Length });
        init.StatusCode.Should().Be(HttpStatusCode.OK, await init.Content.ReadAsStringAsync());
        var sessionId = (await init.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        for (var i = 0; i < chunks.Length; i++)
        {
            var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/storage/upload/{sessionId}/chunk/{i}")
            {
                Content = new ByteArrayContent(chunks[i]),
            };
            request.Headers.Add("X-Chunk-Hash", $"hash-{i}");
            (await client.SendAsync(request)).StatusCode.Should().Be(HttpStatusCode.OK);
        }

        var complete = await client.PostAsJsonAsync($"/api/v1/storage/upload/{sessionId}/complete", new { });
        complete.StatusCode.Should().Be(HttpStatusCode.OK, await complete.Content.ReadAsStringAsync());
        return (await complete.Content.ReadFromJsonAsync<ApiResponse<UploadCompleteDto>>())!.Data!.ManifestHash;
    }

    private async Task ExpireBackoffAsync(Guid fileId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        await db.Database.ExecuteSqlInterpolatedAsync(
            $"""UPDATE photos.photos SET "NextAttemptAt" = now() - interval '1 second' WHERE "FileId" = {fileId} AND "NextAttemptAt" IS NOT NULL""");
    }

    private Task ExecuteFileSqlAsync(string sql) => ExecuteSqlAsync<FileDbContext>(sql);

    private Task ExecutePhotoSqlAsync(string sql) => ExecuteSqlAsync<PhotoDbContext>(sql);

    private async Task ExecuteSqlAsync<TContext>(string sql) where TContext : DbContext
    {
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<TContext>().Database.ExecuteSqlRawAsync(sql);
    }

    private Task ResetCursorAsync() => ExecutePhotoSqlAsync("DELETE FROM photos.ingest_cursors");

    private async Task<IngestCursor> ReadCursorRowAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        return await db.IngestCursors.AsNoTracking().SingleAsync();
    }

    private async Task<long> ReadCursorAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        return (await db.IngestCursors.AsNoTracking().SingleAsync()).LastChangeId;
    }

    private static async Task<long> GetUsedBytesAsync(HttpClient client)
    {
        var response = await client.GetAsync("/api/v1/files/usage");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var usage = await response.Content.ReadFromJsonAsync<ApiResponse<StorageUsageDto>>();
        return usage!.Data!.UsedBytes;
    }

    private sealed record StorageUsageDto(long LimitBytes, long UsedBytes);

    private async Task WaitForBlockedFeedReadAsync(Task pending, CancellationToken cancellationToken)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FileDbContext>();
        while (!pending.IsCompleted)
        {
            var waiting = await db.Database.SqlQueryRaw<int>("""
                SELECT count(*)::int AS "Value" FROM pg_locks
                WHERE relation = 'files.file_changes'::regclass
                  AND mode = 'ShareLock' AND NOT granted
                """).SingleAsync(cancellationToken);
            if (waiting > 0)
                return;
            await Task.Delay(20, cancellationToken);
        }
    }
}
