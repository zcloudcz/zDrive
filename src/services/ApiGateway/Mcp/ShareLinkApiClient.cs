using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ModelContextProtocol;
using ZDrive.Shared.DTOs;

namespace ZDrive.ApiGateway.Mcp;

public enum ShareValidationResult
{
    Ok,
    NotFound,
    Forbidden,
    Unavailable
}

/// <summary>
/// HTTP client the MCP tools use to reach FileService/StorageService's public
/// share-link endpoints. Deliberately thin — it calls the same REST API a
/// human client would, over the wire, with no shortcut through a shared
/// database or project reference (see the contract's "Gateway" section for
/// Package C). Named HttpClients "mcpFileService"/"mcpStorageService" are
/// registered in Program.cs with BaseAddress read from the YARP cluster
/// config, so this class never hardcodes a service URL.
/// </summary>
public sealed class ShareLinkApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    // Not captured once in the constructor: IHttpClientFactory owns handler
    // rotation (DNS refresh, pooled connection recycling), which a singleton
    // holding the HttpClient instances forever would opt out of.
    private readonly IHttpClientFactory _httpClientFactory;

    public ShareLinkApiClient(IHttpClientFactory httpClientFactory) => _httpClientFactory = httpClientFactory;

    private HttpClient FileService => _httpClientFactory.CreateClient("mcpFileService");
    private HttpClient StorageService => _httpClientFactory.CreateClient("mcpStorageService");

    /// <summary>
    /// The cheap pre-check the contract requires before handing a request to
    /// the MCP endpoint: is this token a live, non-password-protected share?
    /// Reuses the existing (already-on-master) GET shares/link/{token} —
    /// deliberately NOT the write-API's GET .../info, which doesn't exist yet
    /// on this branch and would fail validation for reasons unrelated to the
    /// token itself. A backend outage (connection failure, 5xx, timeout) is
    /// reported separately from NotFound — it must not be answered with the
    /// same "unknown token" status the caller would otherwise retry forever
    /// against.
    /// </summary>
    public async Task<ShareValidationResult> ValidateTokenAsync(string token, CancellationToken ct)
    {
        HttpResponseMessage response;
        try
        {
            response = await FileService.GetAsync($"/api/v1/shares/link/{Enc(token)}", ct);
        }
        catch (HttpRequestException)
        {
            return ShareValidationResult.Unavailable;
        }
        catch (TaskCanceledException) when (!ct.IsCancellationRequested)
        {
            // HttpClient.Timeout fires this without cancelling our own token — distinct from the
            // caller actually cancelling the request, which should propagate instead of being swallowed.
            return ShareValidationResult.Unavailable;
        }

        if (response.StatusCode == HttpStatusCode.NotFound) return ShareValidationResult.NotFound;
        if (response.StatusCode == HttpStatusCode.Forbidden) return ShareValidationResult.Forbidden;
        if ((int)response.StatusCode >= 500) return ShareValidationResult.Unavailable;
        response.EnsureSuccessStatusCode();
        return ShareValidationResult.Ok;
    }

    public Task<ShareInfoDto> GetInfoAsync(string token, CancellationToken ct) =>
        SendAsync<ShareInfoDto>(HttpMethod.Get, FileService, $"/api/v1/shares/link/{Enc(token)}/info", null, ct);

    public Task<List<FileDto>> GetChildrenAsync(string token, Guid? folderId, CancellationToken ct)
    {
        var query = folderId is { } id ? $"?folderId={id}" : string.Empty;
        return SendAsync<List<FileDto>>(HttpMethod.Get, FileService, $"/api/v1/shares/link/{Enc(token)}/children{query}", null, ct);
    }

    public Task<ShareDownloadGrantDto> CreateDownloadGrantAsync(string token, Guid fileId, CancellationToken ct) =>
        SendAsync<ShareDownloadGrantDto>(HttpMethod.Post, FileService, $"/api/v1/shares/link/{Enc(token)}/download-grant", new { fileId }, ct);

    public Task<ManifestDto> GetSharedManifestAsync(string grant, CancellationToken ct) =>
        SendWithGrantAsync<ManifestDto>(HttpMethod.Get, StorageService, "/api/v1/storage/shared/manifest", grant, null, ct);

    public async Task<byte[]> DownloadSharedChunkAsync(string grant, string hash, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/storage/shared/chunk/{Enc(hash)}/bytes");
        request.Headers.Add("X-Share-Grant", grant);
        var response = await StorageService.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw await BuildToolErrorAsync(response, ct);
        return await response.Content.ReadAsByteArrayAsync(ct);
    }

    public Task<ShareUploadGrantDto> CreateUploadGrantAsync(
        string token, Guid? parentId, string fileName, long sizeBytes, bool overwrite, CancellationToken ct) =>
        SendAsync<ShareUploadGrantDto>(HttpMethod.Post, FileService, $"/api/v1/shares/link/{Enc(token)}/upload-grant",
            new { parentId, fileName, sizeBytes, overwrite }, ct);

    public Task<UploadSessionDto> InitSharedUploadAsync(string grant, string fileName, int totalChunks, CancellationToken ct) =>
        SendWithGrantAsync<UploadSessionDto>(HttpMethod.Post, StorageService, "/api/v1/storage/shared/upload/init", grant,
            new { fileName, totalChunks }, ct);

    public async Task UploadSharedChunkAsync(string grant, Guid sessionId, int index, string chunkHashHex, byte[] chunkBytes, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/storage/shared/upload/{sessionId}/chunk/{index}");
        request.Headers.Add("X-Share-Grant", grant);
        request.Headers.Add("X-Chunk-Hash", chunkHashHex);
        request.Content = new ByteArrayContent(chunkBytes);
        var response = await StorageService.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw await BuildToolErrorAsync(response, ct);
    }

    public Task<ShareUploadCompleteDto> CompleteSharedUploadAsync(string grant, Guid sessionId, CancellationToken ct) =>
        SendWithGrantAsync<ShareUploadCompleteDto>(HttpMethod.Post, StorageService, $"/api/v1/storage/shared/upload/{sessionId}/complete", grant, null, ct);

    /// <summary>
    /// Best-effort cleanup after a failed chunk upload. Its own failure is
    /// swallowed — there is nothing more to do, and surfacing it would
    /// replace the real error (the chunk failure) with a secondary one.
    /// </summary>
    public async Task AbortSharedUploadAsync(string grant, Guid sessionId, CancellationToken ct)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Delete, $"/api/v1/storage/shared/upload/{sessionId}");
            request.Headers.Add("X-Share-Grant", grant);
            await StorageService.SendAsync(request, ct);
        }
        catch
        {
            // ponytail: best-effort abort; the session simply expires server-side on its own TTL if this also fails
        }
    }

    public Task<FileDto> RecordVersionAsync(string token, Guid fileId, string receipt, CancellationToken ct) =>
        SendAsync<FileDto>(HttpMethod.Post, FileService, $"/api/v1/shares/link/{Enc(token)}/files/{fileId}/versions", new { receipt }, ct);

    public Task<FileDto> CreateFolderAsync(string token, Guid? parentId, string name, CancellationToken ct) =>
        SendAsync<FileDto>(HttpMethod.Post, FileService, $"/api/v1/shares/link/{Enc(token)}/folders", new { parentId, name }, ct);

    public Task DeleteItemAsync(string token, Guid id, CancellationToken ct) =>
        SendAsync<bool>(HttpMethod.Delete, FileService, $"/api/v1/shares/link/{Enc(token)}/items/{id}", null, ct);

    private static string Enc(string value) => Uri.EscapeDataString(value);

    private Task<T> SendAsync<T>(HttpMethod method, HttpClient client, string path, object? body, CancellationToken ct) =>
        SendCoreAsync<T>(method, client, path, grant: null, body, ct);

    private Task<T> SendWithGrantAsync<T>(HttpMethod method, HttpClient client, string path, string grant, object? body, CancellationToken ct) =>
        SendCoreAsync<T>(method, client, path, grant, body, ct);

    private async Task<T> SendCoreAsync<T>(HttpMethod method, HttpClient client, string path, string? grant, object? body, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(method, path);
        if (grant != null) request.Headers.Add("X-Share-Grant", grant);
        if (body != null) request.Content = JsonContent.Create(body, options: JsonOptions);

        var response = await client.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw await BuildToolErrorAsync(response, ct);

        var wrapper = await response.Content.ReadFromJsonAsync<ApiResponse<T>>(JsonOptions, ct);
        return wrapper is { Success: true } ? wrapper.Data! : throw new McpException("The backend returned an unexpected response.");
    }

    /// <summary>
    /// Maps a failed backend call to a plain-language tool error. The backend
    /// error message is passed through when present (e.g. the 413 quota body
    /// already states limit/used bytes per the contract) but never the raw
    /// status alone for statuses whose meaning an LLM wouldn't otherwise
    /// guess. Never includes the token/grant/receipt — those never appear in
    /// a backend error body either (see the contract's "Conventions").
    /// </summary>
    private static async Task<McpException> BuildToolErrorAsync(HttpResponseMessage response, CancellationToken ct)
    {
        string? backendMessage = null;
        try
        {
            var body = await response.Content.ReadFromJsonAsync<ApiResponse<object>>(JsonOptions, ct);
            backendMessage = body?.Error?.Message;
        }
        catch
        {
            // Response body wasn't the ApiResponse envelope (e.g. an empty 404) — fall back below.
        }

        var message = response.StatusCode switch
        {
            HttpStatusCode.Forbidden => "This link does not allow this operation.",
            HttpStatusCode.NotFound => backendMessage ?? "Not found.",
            HttpStatusCode.Conflict => "A file or folder with that name already exists.",
            // The only status whose backend message we pass through: Package B's 413 body
            // states the limit/used numbers, which a fixed message here couldn't reproduce.
            HttpStatusCode.RequestEntityTooLarge => backendMessage ?? "Storage quota exceeded.",
            _ => backendMessage ?? $"Backend request failed ({(int)response.StatusCode})."
        };

        return new McpException(message);
    }
}
