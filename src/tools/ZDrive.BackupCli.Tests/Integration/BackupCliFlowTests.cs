using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Xunit;
using ZDrive.BackupCli.Api;
using ZDrive.BackupCli.Backup;

namespace ZDrive.BackupCli.Tests.Integration;

/// <summary>
/// Exercises the real multi-service flow (login through AuthService, node
/// creation through FileService, chunked upload through StorageService) the
/// way the shipped CLI does — see docs/release-test-deploy.md "Agent 4"
/// acceptance criteria.
/// </summary>
[Trait("Category", "Integration")]
[Collection(nameof(BackupCliCollection))]
public sealed class BackupCliFlowTests : IAsyncLifetime
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private const string Password = "Test1234";

    private readonly BackupCliEnvironment _env;
    private readonly string _root = Directory.CreateTempSubdirectory("zdrive-backup-flow-").FullName;
    private string _email = null!;

    public BackupCliFlowTests(BackupCliEnvironment env) => _env = env;

    public async Task InitializeAsync()
    {
        _email = $"backup-{Guid.NewGuid():N}@zdrive.test";
        using var authClient = _env.AuthFactory.CreateClient();
        var response = await authClient.PostAsJsonAsync("/api/v1/auth/register",
            new { email = _email, password = Password, displayName = "Backup Bot" });
        response.EnsureSuccessStatusCode();
    }

    public Task DisposeAsync()
    {
        Directory.Delete(_root, recursive: true);
        return Task.CompletedTask;
    }

    [Fact]
    public async Task RunAsync_NestedDirectories_DownloadedContentMatchesByteForByte()
    {
        Directory.CreateDirectory(Path.Combine(_root, "sub"));
        var topBytes = "top level file"u8.ToArray();
        var nestedBytes = new byte[1024];
        Random.Shared.NextBytes(nestedBytes);
        await File.WriteAllBytesAsync(Path.Combine(_root, "top.txt"), topBytes);
        await File.WriteAllBytesAsync(Path.Combine(_root, "sub", "nested.bin"), nestedBytes);

        var (api, apiHttp, blobHttp) = BuildClients();
        var exitCode = await new BackupRunner(api, TextWriter.Null, TextWriter.Null)
            .RunAsync(_root, destPath: null, CancellationToken.None);
        exitCode.Should().Be(0);

        var rootChildren = await api.ListChildrenAsync(null, CancellationToken.None);
        var subChildren = await api.ListChildrenAsync(rootChildren["sub"].Id, CancellationToken.None);

        (await DownloadFileContentAsync(apiHttp, blobHttp, rootChildren["top.txt"].Id))
            .Should().BeEquivalentTo(topBytes);
        (await DownloadFileContentAsync(apiHttp, blobHttp, subChildren["nested.bin"].Id))
            .Should().BeEquivalentTo(nestedBytes);
    }

    [Fact]
    public async Task RunAsync_LargeFileSpanningMultipleChunks_DownloadedContentMatches()
    {
        // 2.5x the chunk size so the manifest has 3 chunks, exercising the
        // real init -> chunk -> chunk -> chunk -> complete sequence.
        var content = new byte[(int)(Chunking.ChunkSize * 2.5)];
        Random.Shared.NextBytes(content);
        await File.WriteAllBytesAsync(Path.Combine(_root, "big.bin"), content);

        var (api, apiHttp, blobHttp) = BuildClients();
        var exitCode = await new BackupRunner(api, TextWriter.Null, TextWriter.Null)
            .RunAsync(_root, destPath: null, CancellationToken.None);
        exitCode.Should().Be(0);

        var children = await api.ListChildrenAsync(null, CancellationToken.None);
        (await DownloadFileContentAsync(apiHttp, blobHttp, children["big.bin"].Id))
            .Should().BeEquivalentTo(content);
    }

    [Fact]
    public async Task RunAsync_CalledTwice_SecondRunUploadsNothingNew()
    {
        await File.WriteAllTextAsync(Path.Combine(_root, "file.txt"), "same content, twice");

        var (api1, _, _) = BuildClients();
        (await new BackupRunner(api1, TextWriter.Null, TextWriter.Null)
            .RunAsync(_root, null, CancellationToken.None)).Should().Be(0);

        var stdout = new StringWriter();
        var (api2, _, _) = BuildClients();
        (await new BackupRunner(api2, stdout, TextWriter.Null)
            .RunAsync(_root, null, CancellationToken.None)).Should().Be(0);

        stdout.ToString().Should().Contain("skip");
        stdout.ToString().Should().NotContain("upload ");
    }

    [Fact]
    public async Task RunAsync_KilledMidUpload_NextRunResumesAndCompletes()
    {
        // A file large enough to span multiple chunks, so the "crash" can
        // land after the first chunk but before the upload completes.
        var content = new byte[(int)(Chunking.ChunkSize * 1.5)];
        Random.Shared.NextBytes(content);
        await File.WriteAllBytesAsync(Path.Combine(_root, "resumed.bin"), content);
        await File.WriteAllTextAsync(Path.Combine(_root, "untouched.txt"), "already fine");

        var (killSwitchApi, _, _) = BuildClients();
        var crashingApi = new CrashAfterNChunksApiClient(killSwitchApi, crashAfterChunks: 1);

        // First run "crashes" partway through resumed.bin — an
        // OperationCanceledException is the one failure BackupRunner does
        // NOT swallow per-file (see its catch filter), so it propagates and
        // aborts the whole run exactly like a killed process would: nothing
        // after this point in the run gets touched, including
        // "untouched.txt" even though it sorts after "resumed.bin".
        var firstRun = () => new BackupRunner(crashingApi, TextWriter.Null, TextWriter.Null)
            .RunAsync(_root, null, CancellationToken.None);
        await firstRun.Should().ThrowAsync<OperationCanceledException>();

        // Second run, same account, fresh client — must finish the interrupted
        // file without creating a duplicate node, and without re-touching the
        // file that already completed.
        var (resumedApi, apiHttp, blobHttp) = BuildClients();
        var exitCode = await new BackupRunner(resumedApi, TextWriter.Null, TextWriter.Null)
            .RunAsync(_root, null, CancellationToken.None);
        exitCode.Should().Be(0);

        var children = await resumedApi.ListChildrenAsync(null, CancellationToken.None);
        children.Should().HaveCount(2, "the interrupted file must be resumed on its existing node, not duplicated");
        (await DownloadFileContentAsync(apiHttp, blobHttp, children["resumed.bin"].Id))
            .Should().BeEquivalentTo(content);
    }

    [Fact]
    public async Task Restore_MetadataCommittedBeforeBlobFlip_SecondClientDownloadsRestoredSnapshot()
    {
        var original = "original restored content"u8.ToArray();
        var replacement = "newer replacement content"u8.ToArray();
        var path = Path.Combine(_root, "restore.txt");
        await File.WriteAllBytesAsync(path, original);
        var (writer, writerHttp, writerBlob) = BuildClients();
        using var writerApiLifetime = writerHttp;
        using var writerBlobLifetime = writerBlob;
        var runner = new BackupRunner(writer, TextWriter.Null, TextWriter.Null);
        (await runner.RunAsync(_root, null, CancellationToken.None)).Should().Be(0);
        var fileId = (await writer.ListChildrenAsync(null, CancellationToken.None))["restore.txt"].Id;
        var versions = (await writerHttp.GetFromJsonAsync<ApiEnvelope<JsonElement>>(
            $"files/{fileId}/versions", Json))!.Data;
        var originalVersionId = versions[0].GetProperty("id").GetGuid();
        var originalHash = versions[0].GetProperty("manifestHash").GetString();

        await File.WriteAllBytesAsync(path, replacement);
        (await runner.RunAsync(_root, null, CancellationToken.None)).Should().Be(0);
        using var restore = await writerHttp.PostAsync($"files/{fileId}/versions/{originalVersionId}/restore", null);
        restore.EnsureSuccessStatusCode();
        // Deliberately omit the legacy StorageService flip, reproducing a
        // disconnected restoring client after the metadata transaction.
        var (_, readerHttp, readerBlob) = BuildClients();
        using var readerApiLifetime = readerHttp;
        using var readerBlobLifetime = readerBlob;
        var metadata = (await readerHttp.GetFromJsonAsync<ApiEnvelope<JsonElement>>($"files/{fileId}", Json))!.Data;
        var committedHash = metadata.GetProperty("manifestHash").GetString();
        committedHash.Should().Be(originalHash);
        var snapshot = (await readerHttp.GetFromJsonAsync<ApiEnvelope<JsonElement>>(
            $"storage/download/{fileId}/manifest?manifestHash={committedHash}", Json))!.Data;
        snapshot.GetProperty("manifestHash").GetString().Should().Be(committedHash);
        using var downloaded = new MemoryStream();
        foreach (var chunk in snapshot.GetProperty("chunks").EnumerateArray().OrderBy(c => c.GetProperty("index").GetInt32()))
        {
            var hash = chunk.GetProperty("hash").GetString();
            var bytes = await readerHttp.GetByteArrayAsync($"storage/download/{fileId}/chunk/{hash}/bytes");
            downloaded.Write(bytes);
        }
        downloaded.ToArray().Should().Equal(original);
        // Latest still points at the newer upload: the test cannot pass by
        // accidentally reading manifest.json instead of the pinned snapshot.
        (await DownloadFileContentAsync(readerHttp, readerBlob, fileId)).Should().Equal(replacement);
    }

    private (IZdriveApiClient Api, HttpClient ApiHttp, HttpClient BlobHttp) BuildClients()
    {
        var loginHttp = new HttpClient(new BackupCliGatewayHandler(_env))
        {
            BaseAddress = new Uri("http://backup-cli-test/api/v1/")
        };
        var authClient = new ZdriveAuthClient(loginHttp);
        authClient.LoginAsync(_email, Password, CancellationToken.None).GetAwaiter().GetResult();

        var apiHttp = new HttpClient(new AuthTokenHandler(authClient) { InnerHandler = new BackupCliGatewayHandler(_env) })
        {
            BaseAddress = new Uri("http://backup-cli-test/api/v1/")
        };
        var blobHttp = new HttpClient();
        return (new ZdriveApiClient(apiHttp, blobHttp), apiHttp, blobHttp);
    }

    /// <summary>
    /// Downloads a file the same way a real client would: manifest SAS URL,
    /// then one SAS URL per chunk, concatenated in order. Verification-only —
    /// the shipped CLI never needs to read content back.
    /// </summary>
    private static async Task<byte[]> DownloadFileContentAsync(HttpClient api, HttpClient blob, Guid fileId)
    {
        var manifestUrl = await GetSasUrlAsync(api, $"storage/download/{fileId}");
        var manifestBytes = await (await blob.GetAsync(manifestUrl)).Content.ReadAsByteArrayAsync();
        var manifest = JsonSerializer.Deserialize<RemoteManifest>(manifestBytes, Json)!;

        using var result = new MemoryStream();
        foreach (var chunk in manifest.Chunks.OrderBy(c => c.Index))
        {
            var chunkUrl = await GetSasUrlAsync(api, $"storage/download/{fileId}/chunk/{chunk.Hash}");
            var bytes = await (await blob.GetAsync(chunkUrl)).Content.ReadAsByteArrayAsync();
            result.Write(bytes);
        }
        return result.ToArray();
    }

    private static async Task<string> GetSasUrlAsync(HttpClient api, string path)
    {
        var envelope = await api.GetFromJsonAsync<ApiEnvelope<SasUrlDto>>(path, Json);
        return envelope!.Data!.SasUrl;
    }

    private sealed record SasUrlDto(string SasUrl, DateTime ExpiresAt);

    /// <summary>Throws once a set number of chunks have been uploaded, simulating a process kill mid-upload.</summary>
    private sealed class CrashAfterNChunksApiClient(IZdriveApiClient inner, int crashAfterChunks) : IZdriveApiClient
    {
        private int _uploaded;

        public Task<IReadOnlyDictionary<string, FileNode>> ListChildrenAsync(Guid? parentId, CancellationToken ct) =>
            inner.ListChildrenAsync(parentId, ct);
        public Task<FileNode> CreateFolderAsync(Guid? parentId, string name, CancellationToken ct) =>
            inner.CreateFolderAsync(parentId, name, ct);
        public Task<FileNode> CreateFileNodeAsync(Guid? parentId, string name, long sizeBytes, CancellationToken ct) =>
            inner.CreateFileNodeAsync(parentId, name, sizeBytes, ct);
        public Task CreateFileVersionAsync(Guid fileId, string manifestHash, long sizeBytes, CancellationToken ct) =>
            inner.CreateFileVersionAsync(fileId, manifestHash, sizeBytes, ct);
        public Task<UploadSession> InitUploadAsync(Guid fileId, string fileName, int totalChunks, CancellationToken ct) =>
            inner.InitUploadAsync(fileId, fileName, totalChunks, ct);
        public Task<UploadComplete> CompleteUploadAsync(Guid sessionId, CancellationToken ct) =>
            inner.CompleteUploadAsync(sessionId, ct);
        public Task<RemoteManifestResult?> TryGetManifestAsync(Guid fileId, CancellationToken ct) =>
            inner.TryGetManifestAsync(fileId, ct);
        public Task<bool> HasVersionAsync(Guid fileId, string manifestHash, CancellationToken ct) =>
            inner.HasVersionAsync(fileId, manifestHash, ct);

        public async Task UploadChunkAsync(Guid sessionId, int index, byte[] data, string chunkHash, CancellationToken ct)
        {
            if (_uploaded >= crashAfterChunks)
                throw new OperationCanceledException("Simulated crash mid-upload.");
            await inner.UploadChunkAsync(sessionId, index, data, chunkHash, ct);
            _uploaded++;
        }
    }
}

[CollectionDefinition(nameof(BackupCliCollection))]
public sealed class BackupCliCollection : ICollectionFixture<BackupCliEnvironment>;
