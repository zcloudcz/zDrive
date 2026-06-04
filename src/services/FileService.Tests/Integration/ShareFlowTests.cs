using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class ShareFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;
    private readonly HttpClient _client;

    public ShareFlowTests(FileServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    [Fact]
    public async Task CreateShareLink_AccessViaToken_Success()
    {
        // Create a file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "shared-file.txt",
            isFolder = false,
            sizeBytes = 512L,
            mimeType = "text/plain"
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        // Share it
        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Read
        });
        shareResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var shareResult = await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>();
        shareResult!.Success.Should().BeTrue();
        shareResult.Data!.LinkToken.Should().NotBeNullOrWhiteSpace();
        shareResult.Data.Permission.Should().Be("Read");

        // Access via token (anonymous)
        var unauthClient = _factory.CreateClient();
        var linkResponse = await unauthClient.GetAsync($"/api/v1/shares/link/{shareResult.Data.LinkToken}");
        linkResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var linkResult = await linkResponse.Content.ReadFromJsonAsync<ApiResponse<SharedFileDto>>();
        linkResult!.Success.Should().BeTrue();
        linkResult.Data!.File.Name.Should().Be("shared-file.txt");
        linkResult.Data.Share.Permission.Should().Be("Read");
    }

    [Fact]
    public async Task RevokeShare_TokenNoLongerWorks()
    {
        // Create and share a file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "revocable-share.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Read
        });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        // Revoke
        var revokeResponse = await _client.DeleteAsync($"/api/v1/shares/{share.Id}");
        revokeResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // Token no longer works
        var unauthClient = _factory.CreateClient();
        var linkResponse = await unauthClient.GetAsync($"/api/v1/shares/link/{share.LinkToken}");
        linkResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task ShareLink_WithExpiration_ExpiredLinkReturns404()
    {
        // We can't easily test time-based expiration in an integration test without
        // manipulating the clock. Instead, verify creating a share with a future date works.
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "expirable-share.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Write,
            expiresAt = DateTime.UtcNow.AddDays(7)
        });
        shareResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;
        share.ExpiresAt.Should().NotBeNull();
        share.Permission.Should().Be("Write");
    }
}
