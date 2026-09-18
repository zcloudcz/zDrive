using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Xunit;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Tests.Integration;

/// <summary>
/// Covers the anonymous /api/v1/storage/shared/* endpoints
/// (SharedStorageController), authenticated by a ShareDownloadGrant instead
/// of a JWT. The grant is minted directly here with
/// StorageServiceFactory.TestShareGrantKey (the same key FileService's
/// CreateShareDownloadGrantCommandHandler would sign with in production) —
/// this suite doesn't need FileService running, only StorageService's own
/// validation of a grant it did not itself issue.
/// </summary>
[Trait("Category", "Integration")]
public sealed class SharedDownloadFlowTests : IClassFixture<StorageServiceFactory>
{
    private readonly HttpClient _client;
    private readonly HttpClient _anonClient;
    private readonly string _accessToken;
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly byte[] _key = Convert.FromBase64String(StorageServiceFactory.TestShareGrantKey);

    public SharedDownloadFlowTests(StorageServiceFactory factory)
    {
        _client = factory.CreateClient();
        _anonClient = factory.CreateClient();
        _accessToken = GenerateTestToken(factory.Rsa, _userId, _tenantId);
    }

    [Fact]
    public async Task SharedManifestAndChunks_ValidGrant_ReassembleOriginalBytes()
    {
        var (fileId, manifestHash, chunkData) = await UploadFileAsync("shared.bin", [new byte[1024], new byte[512]]);
        var grant = MakeGrant(fileId, manifestHash, DateTimeOffset.UtcNow.AddHours(1));

        var manifestResponse = await GetShared("manifest", grant);
        manifestResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AssertPublicShareCacheHeaders(manifestResponse);
        var manifest = (await manifestResponse.Content.ReadFromJsonAsync<ApiResponse<ManifestDto>>())!.Data!;
        manifest.Chunks.Should().HaveCount(2);

        foreach (var chunk in manifest.Chunks)
        {
            var chunkResponse = await GetShared($"chunk/{chunk.Hash}/bytes", grant);
            chunkResponse.StatusCode.Should().Be(HttpStatusCode.OK);
            AssertPublicShareCacheHeaders(chunkResponse);
            var bytes = await chunkResponse.Content.ReadAsByteArrayAsync();
            bytes.Should().BeEquivalentTo(chunkData[chunk.Index]);
        }
    }

    [Fact]
    public async Task SharedManifest_TamperedGrant_ReturnsNotFound()
    {
        var (fileId, manifestHash, _) = await UploadFileAsync("tampered.bin", [new byte[64]]);
        var grant = MakeGrant(fileId, manifestHash, DateTimeOffset.UtcNow.AddHours(1));
        // Flip a bit in the signature segment's first byte rather than
        // swapping the grant's last character: for a 32-byte HMAC signature
        // that trailing base64url character carries only 4 significant bits
        // plus 2 always-zero padding bits, so some swaps decode to the exact
        // same bytes and the grant would legitimately still validate.
        var parts = grant.Split('.', 2);
        var tampered = $"{parts[0]}.{FlipFirstByte(parts[1])}";

        var response = await GetShared("manifest", tampered);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        AssertPublicShareCacheHeaders(response);

        var body = await response.Content.ReadAsStringAsync();
        body.Should().NotContain(tampered, "the 404 body must never echo the grant back");
    }

    [Fact]
    public async Task SharedManifest_ExpiredGrant_ReturnsNotFound()
    {
        var (fileId, manifestHash, _) = await UploadFileAsync("expired.bin", [new byte[64]]);
        var grant = MakeGrant(fileId, manifestHash, DateTimeOffset.UtcNow.AddMinutes(-1));

        var response = await GetShared("manifest", grant);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);

        var body = await response.Content.ReadAsStringAsync();
        body.Should().NotContain(grant, "the 404 body must never echo the grant back");
    }

    [Fact]
    public async Task SharedManifest_MissingGrant_ReturnsNotFoundWithNoStoreHeaders()
    {
        var response = await GetShared("manifest", grant: null);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        AssertPublicShareCacheHeaders(response);
    }

    /// <summary>Decodes a base64url segment, flips a bit in its FIRST byte, and re-encodes.</summary>
    private static string FlipFirstByte(string base64UrlSegment)
    {
        var bytes = Base64UrlDecode(base64UrlSegment);
        bytes[0] ^= 0x01;
        return Base64UrlEncode(bytes);
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = padded.PadRight(padded.Length + ((4 - (padded.Length % 4)) % 4), '=');
        return Convert.FromBase64String(padded);
    }

    private static void AssertPublicShareCacheHeaders(HttpResponseMessage response)
    {
        // HttpClient parses Cache-Control into CacheControlHeaderValue and
        // re-serializes it in its own field order on ToString() — "private,
        // no-store" can come back as "no-store, private". Assert the parsed
        // flags instead of the string form.
        response.Headers.CacheControl!.NoStore.Should().BeTrue();
        response.Headers.CacheControl.Private.Should().BeTrue();
        response.Headers.Vary.Should().Contain("X-Share-Grant");
    }

    [Fact]
    public async Task SharedChunk_HashNotInPinnedManifest_ReturnsNotFound()
    {
        // v1: single chunk of 'a's.
        var (fileId, v1Hash, _) = await UploadFileAsync("versioned.bin", [new byte[64]]);

        // v2: re-upload the same fileId with different content, distinct chunk hash.
        var v2Content = new byte[128];
        Random.Shared.NextBytes(v2Content);
        var (_, v2Hash, v2Chunks) = await UploadFileAsync("versioned.bin", [v2Content], fileId);
        v2Hash.Should().NotBe(v1Hash);

        var v1Grant = MakeGrant(fileId, v1Hash, DateTimeOffset.UtcNow.AddHours(1));
        var v2ManifestResponse = await GetShared(
            "manifest", MakeGrant(fileId, v2Hash, DateTimeOffset.UtcNow.AddHours(1)));
        var v2Manifest = (await v2ManifestResponse.Content.ReadFromJsonAsync<ApiResponse<ManifestDto>>())!.Data!;
        var v2OnlyChunkHash = v2Manifest.Chunks.Single().Hash;

        // A grant pinned to v1's manifest must not unlock a chunk that only
        // exists in v2 — even though the chunk hash itself is a real, stored
        // blob (just not part of the version this grant was issued for).
        var response = await GetShared($"chunk/{v2OnlyChunkHash}/bytes", v1Grant);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    private async Task<(Guid FileId, string ManifestHash, byte[][] Chunks)> UploadFileAsync(
        string fileName, byte[][] chunkData, Guid? fileId = null)
    {
        fileId ??= Guid.NewGuid();

        var initResponse = await AuthPost("/api/v1/storage/upload/init", new
        {
            fileId = fileId.Value,
            fileName,
            totalChunks = chunkData.Length
        });
        var sessionId = (await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        for (var i = 0; i < chunkData.Length; i++)
        {
            var chunkContent = new ByteArrayContent(chunkData[i]);
            chunkContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/storage/upload/{sessionId}/chunk/{i}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
            request.Headers.Add("X-Chunk-Hash", $"hash-{i}");
            request.Content = chunkContent;
            await _client.SendAsync(request);
        }

        var completeResponse = await AuthPost($"/api/v1/storage/upload/{sessionId}/complete", new { });
        var complete = (await completeResponse.Content.ReadFromJsonAsync<ApiResponse<UploadCompleteDto>>())!.Data!;

        return (fileId.Value, complete.ManifestHash, chunkData);
    }

    private string MakeGrant(Guid fileId, string manifestHash, DateTimeOffset expiresAt)
    {
        var payload = new ShareDownloadGrant.Payload(_tenantId, _userId, fileId, manifestHash, expiresAt);
        return ShareDownloadGrant.Create(payload, _key);
    }

    private async Task<HttpResponseMessage> GetShared(string path, string? grant)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/storage/shared/{path}");
        if (grant is not null)
            request.Headers.Add("X-Share-Grant", grant);
        return await _anonClient.SendAsync(request);
    }

    private async Task<HttpResponseMessage> AuthPost(string url, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        request.Content = JsonContent.Create(body);
        return await _client.SendAsync(request);
    }

    private static string GenerateTestToken(System.Security.Cryptography.RSA rsa, Guid userId, Guid tenantId)
    {
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
