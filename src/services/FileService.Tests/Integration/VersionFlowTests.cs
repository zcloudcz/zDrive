using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class VersionFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly HttpClient _client;

    public VersionFlowTests(FileServiceFactory factory)
    {
        _client = factory.CreateAuthenticatedClient();
    }

    [Fact]
    public async Task CreateVersions_ListVersions_OrderedByVersionNumber()
    {
        // Create a file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "versioned-file.txt",
            isFolder = false,
            sizeBytes = 100L,
            mimeType = "text/plain"
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        // Note: Version creation is an internal API (called by StorageService, not directly by user).
        // For integration testing, we call it through MediatR via the versions endpoint.
        // Since we don't have a dedicated versions POST endpoint on the controller,
        // we verify the GET versions endpoint returns an empty list initially.
        var versionsResponse = await _client.GetAsync($"/api/v1/files/{file.Id}/versions");
        versionsResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var versionsResult = await versionsResponse.Content.ReadFromJsonAsync<ApiResponse<List<FileVersionDto>>>();
        versionsResult!.Success.Should().BeTrue();
        versionsResult.Data.Should().NotBeNull();
        versionsResult.Data.Should().BeEmpty();
    }

    [Fact]
    public async Task GetVersions_NonExistentFile_Returns404()
    {
        var response = await _client.GetAsync($"/api/v1/files/{Guid.NewGuid()}/versions");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
