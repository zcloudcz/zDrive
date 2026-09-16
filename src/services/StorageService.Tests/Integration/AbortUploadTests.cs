using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Azure.Storage.Blobs;
using FluentAssertions;
using Xunit;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class AbortUploadTests : IClassFixture<StorageServiceFactory>
{
    private readonly StorageServiceFactory _factory;
    private readonly HttpClient _client;

    public AbortUploadTests(StorageServiceFactory factory)
    {
        _factory = factory;
        _client = Client(Guid.NewGuid(), Guid.NewGuid());
    }

    [Fact]
    public async Task AbortUpload_ActiveSession_DeletesOnlyItsTempChunksAndRejectsMoreWrites()
    {
        var session = await Init();
        var other = await Init();
        (await Put(session)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await Put(other)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await _client.DeleteAsync($"/api/v1/storage/upload/{session}")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await Temp(session).ExistsAsync()).Value.Should().BeFalse();
        (await Temp(other).ExistsAsync()).Value.Should().BeTrue();
        (await Put(session)).StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await Complete(session)).StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await _client.DeleteAsync($"/api/v1/storage/upload/{session}")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task AbortUpload_UnknownSession_IsIdempotent()
    {
        (await _client.DeleteAsync($"/api/v1/storage/upload/{Guid.NewGuid()}")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task AbortUpload_ForeignSession_DoesNotDeleteItsData()
    {
        var session = await Init();
        await Put(session);
        using var foreign = Client(Guid.NewGuid(), Guid.NewGuid());
        (await foreign.DeleteAsync($"/api/v1/storage/upload/{session}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await Temp(session).ExistsAsync()).Value.Should().BeTrue();
        (await Complete(session)).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task AbortUpload_ConcurrentChunk_LeavesNoTemporaryData()
    {
        var session = await Init();
        var chunk = Put(session);
        var abort = _client.DeleteAsync($"/api/v1/storage/upload/{session}");
        await Task.WhenAll(chunk, abort);
        (await chunk).StatusCode.Should().BeOneOf(HttpStatusCode.OK, HttpStatusCode.Conflict);
        (await abort).StatusCode.Should().Be(HttpStatusCode.OK);
        (await Temp(session).ExistsAsync()).Value.Should().BeFalse();
    }

    [Fact]
    public async Task AbortUpload_ConcurrentComplete_PreservesCommittedContent()
    {
        var fileId = Guid.NewGuid();
        var session = await Init(fileId);
        await Put(session);
        var complete = Complete(session);
        var abort = _client.DeleteAsync($"/api/v1/storage/upload/{session}");
        await Task.WhenAll(complete, abort);
        (await abort).StatusCode.Should().Be(HttpStatusCode.OK);
        (await complete).StatusCode.Should().BeOneOf(HttpStatusCode.OK, HttpStatusCode.Conflict);
        (await Temp(session).ExistsAsync()).Value.Should().BeFalse();
        if ((await complete).IsSuccessStatusCode)
        {
            (await _client.GetAsync($"/api/v1/storage/download/{fileId}/manifest")).StatusCode.Should().Be(HttpStatusCode.OK);
            (await _client.DeleteAsync($"/api/v1/storage/upload/{session}")).StatusCode.Should().Be(HttpStatusCode.OK);
            (await _client.GetAsync($"/api/v1/storage/download/{fileId}/manifest")).StatusCode.Should().Be(HttpStatusCode.OK);
        }
    }

    [Fact]
    public async Task AbortUpload_CompletedSession_PreservesManifestAndChunk()
    {
        var fileId = Guid.NewGuid();
        var session = await Init(fileId);
        await Put(session);
        (await Complete(session)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await _client.DeleteAsync($"/api/v1/storage/upload/{session}")).StatusCode.Should().Be(HttpStatusCode.OK);
        var response = await _client.GetAsync($"/api/v1/storage/download/{fileId}/manifest");
        response.EnsureSuccessStatusCode();
        var manifest = (await response.Content.ReadFromJsonAsync<ApiResponse<ManifestDto>>())!.Data!;
        var chunk = await _client.GetAsync($"/api/v1/storage/download/{fileId}/chunk/{manifest.Chunks[0].Hash}/bytes");
        (await chunk.Content.ReadAsByteArrayAsync()).Should().Equal(new byte[] { 1, 2, 3 });
    }
    private HttpClient Client(Guid user, Guid tenant)
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _factory.CreateAccessToken(user, tenant));
        return client;
    }

    private async Task<Guid> Init(Guid? fileId = null)
    {
        var response = await _client.PostAsJsonAsync("/api/v1/storage/upload/init", new
        {
            fileId = fileId ?? Guid.NewGuid(), fileName = "video.bin", totalChunks = 1
        });
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;
    }

    private Task<HttpResponseMessage> Put(Guid session)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/storage/upload/{session}/chunk/0")
        {
            Content = new ByteArrayContent(new byte[] { 1, 2, 3 })
        };
        request.Headers.Add("X-Chunk-Hash", "test-hash");
        return _client.SendAsync(request);
    }

    private Task<HttpResponseMessage> Complete(Guid session) =>
        _client.PostAsJsonAsync($"/api/v1/storage/upload/{session}/complete", new { });

    private BlobClient Temp(Guid session) => new BlobServiceClient(_factory.AzuriteConnectionString)
        .GetBlobContainerClient("zdrive-system").GetBlobClient($"temp-uploads/{session}/0");
}
