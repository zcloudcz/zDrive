using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;

namespace ZDrive.BackupCli.Api;

/// <summary>
/// Typed wrapper over the FileService/StorageService endpoints the backup
/// tool needs, replicating the orchestration the Flutter client does in
/// FileRepositoryImpl.uploadFile: create node -> init -> chunks -> complete
/// -> record version.
/// </summary>
public sealed class ZdriveApiClient(HttpClient http, HttpClient blobHttp) : IZdriveApiClient
{
    private const int ListPageSize = 200;

    public async Task<IReadOnlyDictionary<string, FileNode>> ListChildrenAsync(Guid? parentId, CancellationToken ct)
    {
        var basePath = parentId is null ? "files/root/children" : $"files/{parentId}/children";
        var byName = new Dictionary<string, FileNode>();
        var page = 1;
        while (true)
        {
            var result = await GetAsync<PagedResult<FileNode>>($"{basePath}?page={page}&pageSize={ListPageSize}", ct);
            foreach (var item in result.Items)
                byName[item.Name] = item;

            if (byName.Count >= result.TotalCount || result.Items.Count == 0)
                return byName;
            page++;
        }
    }

    public Task<FileNode> CreateFolderAsync(Guid? parentId, string name, CancellationToken ct) =>
        PostAsync<FileNode>("files", new { name, parentId, isFolder = true }, ct);

    public Task<FileNode> CreateFileNodeAsync(Guid? parentId, string name, long sizeBytes, CancellationToken ct) =>
        PostAsync<FileNode>("files", new { name, parentId, isFolder = false, sizeBytes }, ct);

    public Task CreateFileVersionAsync(Guid fileId, string manifestHash, long sizeBytes, CancellationToken ct) =>
        PostAsync<object>($"files/{fileId}/versions",
            new { blobVersionId = manifestHash, sizeBytes, manifestHash }, ct);

    public Task<UploadSession> InitUploadAsync(Guid fileId, string fileName, int totalChunks, CancellationToken ct) =>
        PostAsync<UploadSession>("storage/upload/init", new { fileId, fileName, totalChunks }, ct);

    public async Task UploadChunkAsync(Guid sessionId, int index, byte[] data, string chunkHash, CancellationToken ct)
    {
        using var content = new ByteArrayContent(data);
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
        using var request = new HttpRequestMessage(HttpMethod.Put, $"storage/upload/{sessionId}/chunk/{index}")
        {
            Content = content
        };
        request.Headers.Add("X-Chunk-Hash", chunkHash);
        using var response = await http.SendAsync(request, ct);
        await EnsureSuccessAsync(response, ct);
    }

    public Task<UploadComplete> CompleteUploadAsync(Guid sessionId, CancellationToken ct) =>
        PostAsync<UploadComplete>($"storage/upload/{sessionId}/complete", new { }, ct);

    /// <summary>
    /// Fetches the manifest of a previously completed upload for idempotence
    /// checks. Returns null when the file node exists but no upload ever
    /// completed for it (interrupted run) — the caller should treat that as
    /// "not backed up yet" rather than an error.
    /// </summary>
    public async Task<RemoteManifestResult?> TryGetManifestAsync(Guid fileId, CancellationToken ct)
    {
        var downloadUrl = await GetAsync<DownloadUrl>($"storage/download/{fileId}", ct);
        // The SAS URL points straight at blob storage — a different authority
        // than the gateway, so it must NOT carry our API bearer token.
        using var response = await blobHttp.GetAsync(downloadUrl.SasUrl, ct);
        if (response.StatusCode == HttpStatusCode.NotFound)
            return null;
        response.EnsureSuccessStatusCode();

        var bytes = await response.Content.ReadAsByteArrayAsync(ct);
        var manifest = JsonSerializer.Deserialize<RemoteManifest>(bytes, JsonDefaults.Options)!;
        var manifestHash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        return new RemoteManifestResult(manifest, manifestHash);
    }

    /// <summary>
    /// Checks whether FileService has a version recorded for this exact
    /// content. CompleteUpload (StorageService) and CreateFileVersion
    /// (FileService) are two separate calls — if a run dies in between, the
    /// blob content is already correct but FileService never learned about
    /// it. Without this check a later run would see the matching blob
    /// manifest and skip the file forever, leaving FileService's version
    /// list permanently missing this version.
    /// </summary>
    public async Task<bool> HasVersionAsync(Guid fileId, string manifestHash, CancellationToken ct)
    {
        var versions = await GetAsync<List<FileVersionSummary>>($"files/{fileId}/versions", ct);
        return versions.Any(v => string.Equals(v.ManifestHash, manifestHash, StringComparison.OrdinalIgnoreCase));
    }

    private async Task<T> GetAsync<T>(string path, CancellationToken ct)
    {
        using var response = await http.GetAsync(path, ct);
        return await ReadEnvelopeAsync<T>(response, ct);
    }

    private async Task<T> PostAsync<T>(string path, object body, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(path, body, JsonDefaults.Options, ct);
        return await ReadEnvelopeAsync<T>(response, ct);
    }

    private static async Task<T> ReadEnvelopeAsync<T>(HttpResponseMessage response, CancellationToken ct)
    {
        await EnsureSuccessAsync(response, ct);
        var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<T>>(JsonDefaults.Options, ct);
        if (envelope is not { Success: true })
            throw new ZdriveApiException($"API call failed: {envelope?.Error?.Message ?? "empty response"}.");
        return envelope.Data!;
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken ct)
    {
        if (response.IsSuccessStatusCode)
            return;

        string? message = null;
        try
        {
            var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<object>>(JsonDefaults.Options, ct);
            message = envelope?.Error?.Message;
        }
        catch
        {
            // Body wasn't a JSON envelope — fall back to the status code below.
        }

        throw new ZdriveApiException(
            $"Request to {response.RequestMessage?.RequestUri} failed ({(int)response.StatusCode} {response.StatusCode})" +
            (message is null ? "." : $": {message}"));
    }

    private sealed record DownloadUrl(string SasUrl, DateTime ExpiresAt);
}
