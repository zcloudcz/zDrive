using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Xunit;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class UploadFlowTests : IClassFixture<StorageServiceFactory>
{
    private readonly HttpClient _client;
    private readonly string _accessToken;
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _tenantId = Guid.NewGuid();

    public UploadFlowTests(StorageServiceFactory factory)
    {
        _client = factory.CreateClient();
        _accessToken = GenerateTestToken(_userId, _tenantId);
    }

    [Fact]
    public async Task InitUpload_Upload3Chunks_Complete_DownloadUrl_FullFlow()
    {
        var fileId = Guid.NewGuid();
        var chunkData = new byte[][] {
            new byte[1024],
            new byte[1024],
            new byte[512]
        };
        Random.Shared.NextBytes(chunkData[0]);
        Random.Shared.NextBytes(chunkData[1]);
        Random.Shared.NextBytes(chunkData[2]);

        // Init upload
        var initResponse = await AuthPost("/api/v1/storage/upload/init", new
        {
            fileId,
            fileName = "test-document.pdf",
            totalChunks = 3
        });
        initResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var initResult = await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>();
        initResult.Should().NotBeNull();
        initResult!.Success.Should().BeTrue();
        initResult.Data.Should().NotBeNull();
        var sessionId = initResult.Data!.SessionId;
        sessionId.Should().NotBe(Guid.Empty);
        initResult.Data.SasUploadUrl.Should().NotBeNullOrWhiteSpace();

        // Upload 3 chunks
        for (var i = 0; i < 3; i++)
        {
            var chunkContent = new ByteArrayContent(chunkData[i]);
            chunkContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");

            var request = new HttpRequestMessage(HttpMethod.Put,
                $"/api/v1/storage/upload/{sessionId}/chunk/{i}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
            request.Headers.Add("X-Chunk-Hash", $"hash-{i}");
            request.Content = chunkContent;

            var chunkResponse = await _client.SendAsync(request);
            chunkResponse.StatusCode.Should().Be(HttpStatusCode.OK,
                $"Chunk {i} upload failed: {await chunkResponse.Content.ReadAsStringAsync()}");

            var chunkResult = await chunkResponse.Content.ReadFromJsonAsync<ApiResponse<ChunkUploadResultDto>>();
            chunkResult!.Success.Should().BeTrue();
            chunkResult.Data!.Accepted.Should().BeTrue();
            chunkResult.Data.ChunkIndex.Should().Be(i);
        }

        // Complete upload
        var completeResponse = await AuthPost($"/api/v1/storage/upload/{sessionId}/complete", new { });
        completeResponse.StatusCode.Should().Be(HttpStatusCode.OK,
            $"Complete upload failed: {await completeResponse.Content.ReadAsStringAsync()}");

        var completeResult = await completeResponse.Content.ReadFromJsonAsync<ApiResponse<UploadCompleteDto>>();
        completeResult!.Success.Should().BeTrue();
        completeResult.Data.Should().NotBeNull();
        completeResult.Data!.BlobPath.Should().Contain(fileId.ToString());
        completeResult.Data.ManifestHash.Should().NotBeNullOrWhiteSpace();
        completeResult.Data.TotalSize.Should().Be(1024 + 1024 + 512);

        // Get download URL
        var downloadResponse = await AuthGet($"/api/v1/storage/download/{fileId}");
        downloadResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var downloadResult = await downloadResponse.Content.ReadFromJsonAsync<ApiResponse<DownloadUrlDto>>();
        downloadResult!.Success.Should().BeTrue();
        downloadResult.Data!.SasUrl.Should().NotBeNullOrWhiteSpace();
        downloadResult.Data.ExpiresAt.Should().BeAfter(DateTime.UtcNow);
    }

    [Fact]
    public async Task CompleteUpload_MissingChunks_ReturnsConflict()
    {
        var fileId = Guid.NewGuid();

        // Init upload with 3 chunks
        var initResponse = await AuthPost("/api/v1/storage/upload/init", new
        {
            fileId,
            fileName = "incomplete.pdf",
            totalChunks = 3
        });
        var initResult = await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>();
        var sessionId = initResult!.Data!.SessionId;

        // Upload only 1 chunk (missing 2)
        var chunkContent = new ByteArrayContent(new byte[512]);
        chunkContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        var chunkRequest = new HttpRequestMessage(HttpMethod.Put,
            $"/api/v1/storage/upload/{sessionId}/chunk/0");
        chunkRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        chunkRequest.Headers.Add("X-Chunk-Hash", "hash-0");
        chunkRequest.Content = chunkContent;
        await _client.SendAsync(chunkRequest);

        // Try to complete — should fail because chunk 1 and 2 are missing
        var completeResponse = await AuthPost($"/api/v1/storage/upload/{sessionId}/complete", new { });
        completeResponse.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task DeleteBlob_AfterUpload_ReturnsOk()
    {
        var fileId = Guid.NewGuid();

        // Init + upload 1 chunk + complete
        var initResponse = await AuthPost("/api/v1/storage/upload/init", new
        {
            fileId,
            fileName = "to-delete.txt",
            totalChunks = 1
        });
        var initResult = await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>();
        var sessionId = initResult!.Data!.SessionId;

        var chunkContent = new ByteArrayContent(new byte[256]);
        chunkContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        var chunkRequest = new HttpRequestMessage(HttpMethod.Put,
            $"/api/v1/storage/upload/{sessionId}/chunk/0");
        chunkRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        chunkRequest.Headers.Add("X-Chunk-Hash", "hash-0");
        chunkRequest.Content = chunkContent;
        await _client.SendAsync(chunkRequest);

        await AuthPost($"/api/v1/storage/upload/{sessionId}/complete", new { });

        // Delete
        var deleteResponse = await AuthDelete($"/api/v1/storage/{fileId}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var deleteResult = await deleteResponse.Content.ReadFromJsonAsync<ApiResponse<bool>>();
        deleteResult!.Success.Should().BeTrue();
        deleteResult.Data.Should().BeTrue();
    }

    [Fact]
    public async Task UploadChunk_NonExistentSession_Returns404()
    {
        var fakeSessionId = Guid.NewGuid();
        var chunkContent = new ByteArrayContent(new byte[100]);
        chunkContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");

        var request = new HttpRequestMessage(HttpMethod.Put,
            $"/api/v1/storage/upload/{fakeSessionId}/chunk/0");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        request.Headers.Add("X-Chunk-Hash", "hash-0");
        request.Content = chunkContent;

        var response = await _client.SendAsync(request);
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Endpoints_WithoutToken_Return401()
    {
        var response = await _client.GetAsync($"/api/v1/storage/download/{Guid.NewGuid()}");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private async Task<HttpResponseMessage> AuthPost(string url, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        request.Content = JsonContent.Create(body);
        return await _client.SendAsync(request);
    }

    private async Task<HttpResponseMessage> AuthGet(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        return await _client.SendAsync(request);
    }

    private async Task<HttpResponseMessage> AuthDelete(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        return await _client.SendAsync(request);
    }

    /// <summary>
    /// Generates a test JWT token using the same dev key that the service validates against.
    /// </summary>
    private static string GenerateTestToken(Guid userId, Guid tenantId)
    {
        var rsa = RSA.Create();
        rsa.ImportFromPem(@"-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA0Z3VS5JJcds3xfn/ygWep4PAtGoSo1YFqFiGQoL0wn1jOiRi
LMJS4TjfEgLDBUkHaAMixGRdAi60BKMY69CYfSXkBHQOKDYDaFMVr2KFaFNpiGpj
saW9Dg8s7QEXkzuxOMETJYIK3SQIT3REiN0XSDBuVQFutnJmNoRahWzZfJFO+04q
qjfONKrT6JnKqDPR8TN3NB1tWFGVfCKbj/W0OqGqVoPHmm1VhQ6VvpXk3ARz+OG
OW0bexW3RJkShjkTA7cXRPLRf4BGORXKNX3W1A6LSGZdzq3aB0apu1MRfWACGx2o
hWMqW9IxWRcL6lMxjSjiPXbJxekwyjJ6k4URPQIDAQABAoIBAGQH+PBNb4sJLu3r
mEnsJMCuJPUXQIFb1qXBERcX5y+PxNHjn6Qu3ZfgPQj+m6OnaFAi/yvHBHkTVJKy
j6qhXJBtNHLDdFaXHVs5p+E9LB0VD9i4k3C7gZ1S1FH9aM8ZDW+MpHf7YR+p7oD
jjQUyxHR4XLUYf/suPb4kUjGcA4uY/sBFJR8HDd+5JBJy9OQ7YP/CuGJjAk7d+yy
PCVuVCOjCG4nFLR5NZpGJ9pOsRQ3pSHRbMh38fOR9EZE7GBD6M6pA3gzQomB0W8v
REt/M5lh7lo/bUXaIaE4m6E5M+NXLGCM/VL/8B+sdfVNxEC0OzOH5OcZYOgZuBX/
kpfVTgECgYEA7HW+9PGkIAHqFiWoiRyT/bHI3B0FMEz2viS4vJ0TjIOEWTaHxojD
XjWRNG1TGiL8PoVfb4DMRK4gFMVpqJQ1O5s2hy7zCIRUjNi0FLB/S9e0t4DB2NXe
JDsqIh/J63JKQVQ8pGBMwIJp9SoqEJUZBGRRAzjwV6p+ZemIqjGR30CgYEA4uTN
QY3J4H4oSCIon0JnR4gqYfKam9Gp0SMCfvXrcGGnIiC6SlRjxOGsYO1b3J9Kwtx/
P/KaJc6HFXy/QcWYG35aKfCBdHGnU3iKS7w8F9s2wT5XkmRb7jMgOdJEz1qnCfy0
JWOHxN5gPEMjwBn0eM/PVAaIVNYLOsFc0bOjVQECgYBw3Dz+JNPFjC90lPIiqbN5
BQ8rnB3x1XSJNSBqLJG5RFaJNJZ4bPwEVoiUJCjVdzrg1JVMKfj53CIvhGpviHVB
E7fKmJhYbN0g5Hba+aSBKcNcBX1OEh1p47D/2umj0wiN4/hlGAJHTjIq7Q0F3FZl
J0oFdKQkkJxkiE2dVUMvXQKBgCm0S91pRX1VDfJ7kSLtjOcd6bGDmbJvIVaIYEy0
JbNFfz5L9p7u4CxIiKDJC1kYfz3C+vxJJCeAz3S/mtBv7/OzN3l1XhJR9DlKUU5a
eaenJo0Y7Q7y3/HB7FUNfVnEGxJ/hPhbW68BmR0sIpMBkV0bPYhqjKPRblzRNMKB
AoGBAL+sHIjhkxZA0RnDFfSHUFHRSrVz0FO/juFXBe1c0Bh48IvSjkPQVXaRRnHU
v+DYf60t4LZ5LiIF1FGBJMmqaDIK8DFqMW7vGjM0HVlkb0cJfD3kJd1Eiw/NyRpR
f9OY/MN4eNQjx5jx3LKzXaMrDqaJU95kCL79k5SZILQ/e2Rb
-----END RSA PRIVATE KEY-----");

        var credentials = new SigningCredentials(new RsaSecurityKey(rsa), SecurityAlgorithms.RsaSha256);

        var claims = new[]
        {
            new Claim("sub", userId.ToString()),
            new Claim("tenant_id", tenantId.ToString()),
            new Claim("role", "Owner"),
            new Claim("display_name", "Test User")
        };

        var token = new JwtSecurityToken(
            issuer: "zdrive",
            audience: "zdrive-api",
            claims: claims,
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
