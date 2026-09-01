using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Xunit;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.PhotoService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class AlbumsFlowTests : IClassFixture<PhotoServiceFactory>
{
    private readonly PhotoServiceFactory _factory;
    private readonly HttpClient _client;

    public AlbumsFlowTests(PhotoServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    private async Task<AlbumDto> CreateAlbumAsync(string name = "Vacation")
    {
        var response = await _client.PostAsJsonAsync("/api/v1/albums", new { name });
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<AlbumDto>())!;
    }

    private async Task<PhotoDto> IngestPhotoAsync(string fileName = "album-photo.jpg")
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
    public async Task Create_ValidName_AppearsInGetAll()
    {
        var album = await CreateAlbumAsync("Create_ValidName");

        var listResponse = await _client.GetAsync("/api/v1/albums");
        listResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var albums = await listResponse.Content.ReadFromJsonAsync<List<AlbumDto>>();
        albums.Should().Contain(a => a.Id == album.Id && a.Name == "Create_ValidName");
    }

    [Fact]
    public async Task Create_EmptyName_Returns400()
    {
        var response = await _client.PostAsJsonAsync("/api/v1/albums", new { name = "" });
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task AddPhotos_ExistingAlbumAndPhoto_AppearsInGetPhotos()
    {
        var album = await CreateAlbumAsync("AddPhotos_Existing");
        var photo = await IngestPhotoAsync();

        var addResponse = await _client.PostAsJsonAsync($"/api/v1/albums/{album.Id}/photos", new
        {
            photoIds = new[] { photo.Id }
        });
        addResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var photosResponse = await _client.GetAsync($"/api/v1/albums/{album.Id}/photos");
        photosResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var photos = await photosResponse.Content.ReadFromJsonAsync<PagedResult<PhotoDto>>();
        photos!.Items.Should().Contain(p => p.Id == photo.Id);
    }

    [Fact]
    public async Task AddPhotos_PhotoOwnedByAnotherUser_IsAddedAnyway()
    {
        // Documents a known gap (see report): AddPhotosToAlbumCommandHandler only
        // checks that the photo exists globally, not that it belongs to the
        // calling user/tenant. Not fixed here — out of scope for this task.
        var album = await CreateAlbumAsync("AddPhotos_ForeignPhoto");

        using var foreignClient = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var foreignPhotoResponse = await foreignClient.PostAsJsonAsync("/api/v1/photos/ingest", new
        {
            fileId = Guid.NewGuid(),
            originalFileName = "not-yours.jpg",
            blobPath = "/tenant/other/not-yours.jpg"
        });
        var foreignPhoto = (await foreignPhotoResponse.Content.ReadFromJsonAsync<PhotoDto>())!;

        var addResponse = await _client.PostAsJsonAsync($"/api/v1/albums/{album.Id}/photos", new
        {
            photoIds = new[] { foreignPhoto.Id }
        });

        addResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var added = await addResponse.Content.ReadFromJsonAsync<JsonElement>();
        added.GetProperty("added").GetInt32().Should().Be(1);
    }

    [Fact]
    public async Task AddPhotos_NonExistingAlbum_Returns404()
    {
        var photo = await IngestPhotoAsync();

        var response = await _client.PostAsJsonAsync($"/api/v1/albums/{Guid.NewGuid()}/photos", new
        {
            photoIds = new[] { photo.Id }
        });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetPhotos_NonExistingAlbum_Returns404()
    {
        var response = await _client.GetAsync($"/api/v1/albums/{Guid.NewGuid()}/photos");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task RemovePhoto_ExistingAssociation_NoLongerInGetPhotos()
    {
        var album = await CreateAlbumAsync("RemovePhoto_Existing");
        var photo = await IngestPhotoAsync();
        await _client.PostAsJsonAsync($"/api/v1/albums/{album.Id}/photos", new { photoIds = new[] { photo.Id } });

        var removeResponse = await _client.DeleteAsync($"/api/v1/albums/{album.Id}/photos/{photo.Id}");
        removeResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var photosResponse = await _client.GetAsync($"/api/v1/albums/{album.Id}/photos");
        var photos = await photosResponse.Content.ReadFromJsonAsync<PagedResult<PhotoDto>>();
        photos!.Items.Should().NotContain(p => p.Id == photo.Id);
    }

    [Fact]
    public async Task RemovePhoto_NonExistingAlbum_Returns404()
    {
        var response = await _client.DeleteAsync($"/api/v1/albums/{Guid.NewGuid()}/photos/{Guid.NewGuid()}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Update_RenameAlbum_ReturnsUpdatedName()
    {
        var album = await CreateAlbumAsync("Update_OldName");

        var response = await _client.PutAsJsonAsync($"/api/v1/albums/{album.Id}", new { name = "Update_NewName" });
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var updated = await response.Content.ReadFromJsonAsync<AlbumDto>();
        updated!.Name.Should().Be("Update_NewName");
    }

    [Fact]
    public async Task Update_NonExistingAlbum_Returns404()
    {
        var response = await _client.PutAsJsonAsync($"/api/v1/albums/{Guid.NewGuid()}", new { name = "X" });
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Delete_ExistingAlbum_NoLongerInGetAll()
    {
        var album = await CreateAlbumAsync("Delete_Existing");

        var deleteResponse = await _client.DeleteAsync($"/api/v1/albums/{album.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var listResponse = await _client.GetAsync("/api/v1/albums");
        var albums = await listResponse.Content.ReadFromJsonAsync<List<AlbumDto>>();
        albums.Should().NotContain(a => a.Id == album.Id);
    }

    [Fact]
    public async Task Delete_NonExistingAlbum_Returns404()
    {
        var response = await _client.DeleteAsync($"/api/v1/albums/{Guid.NewGuid()}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Delete_AlbumOwnedByAnotherUser_Returns404()
    {
        // Ownership is enforced by filtering on UserId in the query, not by a
        // separate authorization check — a foreign album looks the same as a
        // missing one (404, not 403).
        var album = await CreateAlbumAsync("Delete_ForeignOwner");

        using var foreignClient = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var response = await foreignClient.DeleteAsync($"/api/v1/albums/{album.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
