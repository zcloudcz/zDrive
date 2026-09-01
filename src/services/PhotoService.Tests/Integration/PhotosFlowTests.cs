using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.PhotoService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class PhotosFlowTests : IClassFixture<PhotoServiceFactory>
{
    private readonly PhotoServiceFactory _factory;
    private readonly HttpClient _client;

    public PhotosFlowTests(PhotoServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    private async Task<PhotoDto> IngestPhotoAsync(string fileName = "beach.jpg")
    {
        var response = await _client.PostAsJsonAsync("/api/v1/photos/ingest", new
        {
            fileId = Guid.NewGuid(),
            originalFileName = fileName,
            blobPath = $"/tenant/user/{fileName}"
        });
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<PhotoDto>())!;
    }

    [Fact]
    public async Task Ingest_ValidPayload_AppearsInTimeline()
    {
        var photo = await IngestPhotoAsync();

        var timelineResponse = await _client.GetAsync("/api/v1/photos/timeline?limit=200");
        timelineResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var timeline = await timelineResponse.Content.ReadFromJsonAsync<TimelineResultDto>();
        timeline!.Photos.Should().Contain(p => p.Id == photo.Id);
    }

    [Fact]
    public async Task Ingest_EmptyOriginalFileName_Returns400()
    {
        var response = await _client.PostAsJsonAsync("/api/v1/photos/ingest", new
        {
            fileId = Guid.NewGuid(),
            originalFileName = "",
            blobPath = "/tenant/user/x.jpg"
        });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GetById_ExistingPhoto_ReturnsPhoto()
    {
        var photo = await IngestPhotoAsync("mountains.jpg");

        var response = await _client.GetAsync($"/api/v1/photos/{photo.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var result = await response.Content.ReadFromJsonAsync<PhotoDto>();
        result!.OriginalFileName.Should().Be("mountains.jpg");
    }

    [Fact]
    public async Task GetById_NonExistingPhoto_Returns404()
    {
        var response = await _client.GetAsync($"/api/v1/photos/{Guid.NewGuid()}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetById_PhotoOwnedByAnotherUser_Returns404()
    {
        var photo = await IngestPhotoAsync("foreign-owner.jpg");

        using var foreignClient = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var response = await foreignClient.GetAsync($"/api/v1/photos/{photo.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetTimeline_NonUtcFromOffset_ConvertedToCorrectInstant()
    {
        var photo = await IngestPhotoAsync("timezone-check.jpg");

        // Same instant as "30 seconds ago", but expressed with a +10:00 offset
        // so the wall-clock component reads ~10 hours ahead of UTC. If the
        // controller used the raw wall-clock value instead of converting to
        // UTC, this photo (CreatedAt ~= now) would incorrectly be filtered out.
        var from = DateTimeOffset.UtcNow.AddSeconds(-30).ToOffset(TimeSpan.FromHours(10));
        var url = $"/api/v1/photos/timeline?from={Uri.EscapeDataString(from.ToString("o"))}";

        var response = await _client.GetAsync(url);
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var timeline = await response.Content.ReadFromJsonAsync<TimelineResultDto>();
        timeline!.Photos.Should().Contain(p => p.Id == photo.Id);
    }

    [Fact]
    public async Task GetTimeline_LimitOutOfRange_Returns400()
    {
        var response = await _client.GetAsync("/api/v1/photos/timeline?limit=0");
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Search_TaggedPhoto_ReturnsMatchByTag()
    {
        var photo = await IngestPhotoAsync("sunset.jpg");
        await _client.PostAsJsonAsync($"/api/v1/photos/{photo.Id}/tags", new
        {
            tag = "sunset-search-marker",
            confidence = 1.0f,
            source = 1 // Manual
        });

        var response = await _client.GetAsync("/api/v1/photos/search?q=sunset-search-marker");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var result = await response.Content.ReadFromJsonAsync<PagedResult<PhotoDto>>();
        result!.Items.Should().Contain(p => p.Id == photo.Id);
    }

    [Fact]
    public async Task Search_EmptyQuery_Returns400()
    {
        var response = await _client.GetAsync("/api/v1/photos/search?q=");
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Search_PageSizeTooLarge_Returns400()
    {
        var response = await _client.GetAsync("/api/v1/photos/search?q=anything&pageSize=201");
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task AddTag_ExistingPhoto_ReturnsManualTag()
    {
        var photo = await IngestPhotoAsync("dog.jpg");

        var response = await _client.PostAsJsonAsync($"/api/v1/photos/{photo.Id}/tags", new
        {
            tag = "dog",
            confidence = 1.0f,
            source = 1 // Manual
        });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var tag = await response.Content.ReadFromJsonAsync<PhotoTagDto>();
        tag!.Tag.Should().Be("dog");
        tag.Source.Should().Be("Manual");
    }

    [Fact]
    public async Task AddTag_ConfidenceOutOfRange_Returns400()
    {
        var photo = await IngestPhotoAsync("cat.jpg");

        var response = await _client.PostAsJsonAsync($"/api/v1/photos/{photo.Id}/tags", new
        {
            tag = "cat",
            confidence = 2.0f, // valid range is 0..1
            source = 1
        });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task AddTag_PhotoOwnedByAnotherUser_SucceedsAnyway()
    {
        // Documents a known gap (see report): AddTagCommandHandler only checks
        // that the photo exists globally, not that it belongs to the calling
        // user/tenant. Not fixed here — out of scope for this task.
        var photo = await IngestPhotoAsync("foreign-tag-target.jpg");

        using var foreignClient = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var response = await foreignClient.PostAsJsonAsync($"/api/v1/photos/{photo.Id}/tags", new
        {
            tag = "not-my-photo",
            confidence = 1.0f,
            source = 1
        });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task AddTag_NonExistingPhoto_Returns404()
    {
        var response = await _client.PostAsJsonAsync($"/api/v1/photos/{Guid.NewGuid()}/tags", new
        {
            tag = "dog",
            confidence = 1.0f,
            source = 1
        });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetTimeline_WithoutAuth_Returns401()
    {
        // No bearer token attached — reuses the shared fixture's server instead
        // of spinning up a second Postgres container just for this check.
        using var unauthClient = _factory.CreateClient();
        var response = await unauthClient.GetAsync("/api/v1/photos/timeline");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
