using System.ComponentModel;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace ZDrive.ApiGateway.Mcp;

/// <summary>
/// The MCP tools an AI agent gets for a share link (see the contract's
/// "Package C" section for names/behaviour — they are binding). Every call
/// operates on the token the ShareTokenAuth middleware already validated for
/// this request and stashed on HttpContext.Items — tools never see or
/// validate the token themselves, and never log it (see BuildToolErrorAsync
/// in ShareLinkApiClient for the same rule on backend errors).
/// </summary>
[McpServerToolType]
public sealed class ShareLinkTools
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private const int ChunkSize = 4 * 1024 * 1024;

    // ponytail: each inline transfer costs ~3-4x the file's size in RAM (raw bytes +
    // base64 string + the JSON-RPC envelope around it), and the gateway fronts every
    // other request on the same memory-bound plan — 2 concurrent transfers is a
    // deliberately small cap, not a measured one. Raise it (or make it configurable)
    // if MCP transfer throughput actually matters.
    private static readonly SemaphoreSlim TransferConcurrencyGate = new(2, 2);

    private readonly ShareLinkApiClient _api;
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly McpOptions _options;
    private readonly ILogger<ShareLinkTools> _logger;

    public ShareLinkTools(
        ShareLinkApiClient api,
        IHttpContextAccessor httpContextAccessor,
        IOptions<McpOptions> options,
        ILogger<ShareLinkTools> logger)
    {
        _api = api;
        _httpContextAccessor = httpContextAccessor;
        _options = options.Value;
        _logger = logger;
    }

    private string Token =>
        _httpContextAccessor.HttpContext?.Items[ShareTokenAuth.TokenItemKey] as string
        ?? throw new McpException("No validated share token on this request.");

    [McpServerTool, Description("Get information about this share link: permission level, whether delete is allowed, expiry, the shared root item, and (when known) the owner's storage quota.")]
    public async Task<string> get_info(CancellationToken ct)
    {
        var info = await _api.GetInfoAsync(Token, ct);
        _logger.LogInformation("MCP tool {Tool} succeeded", nameof(get_info));
        return JsonSerializer.Serialize(info, JsonOptions);
    }

    [McpServerTool, Description("List the files and folders inside a folder. folderId is an id returned by a previous list_files/create_folder call, not a path — omit it to list the shared root.")]
    public async Task<string> list_files(Guid? folderId = null, CancellationToken ct = default)
    {
        var children = await _api.GetChildrenAsync(Token, folderId, ct);
        var compact = children.Select(f => new { f.Id, f.Name, f.IsFolder, f.SizeBytes, modifiedAt = f.UpdatedAt });
        _logger.LogInformation("MCP tool {Tool} succeeded, {Count} items", nameof(list_files), children.Count);
        return JsonSerializer.Serialize(compact, JsonOptions);
    }

    [McpServerTool, Description("Read a file's content by id (ids come from list_files, files have no paths). encoding \"auto\" (default) returns text for valid UTF-8 content and base64 otherwise; \"text\" or \"base64\" force that encoding. Files over the inline size limit are refused — use the REST API for those.")]
    public async Task<string> read_file(Guid fileId, string encoding = "auto", CancellationToken ct = default)
    {
        await TransferConcurrencyGate.WaitAsync(ct);
        try
        {
            var grant = await _api.CreateDownloadGrantAsync(Token, fileId, ct);
            var manifest = await _api.GetSharedManifestAsync(grant.Grant, ct);

            if (manifest.TotalSize > _options.MaxInlineBytes)
            {
                throw new McpException(
                    $"File is {manifest.TotalSize} bytes, over the {_options.MaxInlineBytes}-byte inline limit — use the REST API to download it instead.");
            }

            var bytes = await DownloadVerifiedAsync(grant.Grant, manifest, ct);

            var (content, usedEncoding) = encoding switch
            {
                "text" => (Encoding.UTF8.GetString(bytes), "text"),
                "base64" => (Convert.ToBase64String(bytes), "base64"),
                "auto" or "" or null => TryDecodeStrictUtf8(bytes, out var decoded) ? (decoded, "text") : (Convert.ToBase64String(bytes), "base64"),
                _ => throw new McpException("encoding must be \"auto\", \"text\" or \"base64\".")
            };

            _logger.LogInformation("MCP tool {Tool} succeeded, {Bytes} bytes, encoding {Encoding}", nameof(read_file), bytes.LongLength, usedEncoding);

            return JsonSerializer.Serialize(
                new { fileId, name = grant.FileName, sizeBytes = bytes.LongLength, encoding = usedEncoding, content },
                JsonOptions);
        }
        finally
        {
            TransferConcurrencyGate.Release();
        }
    }

    /// <summary>
    /// Downloads every chunk in the manifest, verifies each one's SHA-256, and
    /// checks the assembled result against the manifest's declared total size —
    /// mirroring assembleVerifiedFileStream in the Flutter client
    /// (file_upload_data_source.dart), which the public share-link download path
    /// must apply the same corruption checks as. A MemoryStream (not a
    /// pre-sized byte[]) is used deliberately: the manifest carries no
    /// per-chunk size, so a corrupt/malicious manifest whose chunks would
    /// overflow the declared total must be caught explicitly (below) rather
    /// than relying on an ArgumentException from a fixed-size array copy.
    /// </summary>
    private async Task<byte[]> DownloadVerifiedAsync(string grant, ManifestDto manifest, CancellationToken ct)
    {
        var chunks = manifest.Chunks.OrderBy(c => c.Index).ToList();

        // Indices must be exactly 0..n-1: unique, contiguous, zero-based. Chunks are a
        // fixed size, so without this a manifest repeating one index — [{0,A},{0,A}] —
        // would assemble to A||A at exactly the size A||B would have been, with every
        // individual chunk still hashing correctly.
        for (var i = 0; i < chunks.Count; i++)
        {
            if (chunks[i].Index != i)
                throw new McpException("File content is incomplete: the chunk manifest is not contiguous.");
        }

        using var buffer = new MemoryStream();
        foreach (var chunk in chunks)
        {
            var chunkBytes = await _api.DownloadSharedChunkAsync(grant, chunk.Hash, ct);
            var actualHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(chunkBytes)).ToLowerInvariant();
            if (!string.Equals(actualHash, chunk.Hash, StringComparison.OrdinalIgnoreCase))
                throw new McpException("A downloaded chunk failed integrity verification.");

            // Reject before copying: a chunk that would push the assembled size past
            // the manifest's declared total means the manifest itself is not trustworthy.
            if (buffer.Length + chunkBytes.Length > manifest.TotalSize)
                throw new McpException("File content is incomplete: the chunk manifest does not match its declared size.");

            buffer.Write(chunkBytes);
        }

        // Per-chunk hashing only proves each chunk's own bytes are intact — it says
        // nothing about whether the *set* of chunks is complete. Together with the
        // index check above (which catches duplicates/gaps at equal total size), this
        // catches a truncated manifest and an empty chunk list for a non-empty file.
        if (buffer.Length != manifest.TotalSize)
            throw new McpException("File content is incomplete: the chunk manifest does not match its declared size.");

        return buffer.ToArray();
    }

    [McpServerTool, Description("Create a file with the given content, or overwrite an existing one (overwrite=true required). content is text or base64 per encoding. parentId is a folder id from list_files (omit for the shared root). Content over the inline size limit is refused — use the REST API for those.")]
    public async Task<string> write_file(
        string name, string content, string encoding = "text", Guid? parentId = null, bool overwrite = false, CancellationToken ct = default)
    {
        var bytes = encoding switch
        {
            "text" or "" or null => Encoding.UTF8.GetBytes(content),
            "base64" => Convert.FromBase64String(content),
            _ => throw new McpException("encoding must be \"text\" or \"base64\".")
        };

        if (bytes.LongLength > _options.MaxInlineBytes)
        {
            throw new McpException(
                $"Content is {bytes.LongLength} bytes, over the {_options.MaxInlineBytes}-byte inline limit — use the REST API to upload it instead.");
        }

        await TransferConcurrencyGate.WaitAsync(ct);
        try
        {
            var grant = await _api.CreateUploadGrantAsync(Token, parentId, name, bytes.LongLength, overwrite, ct);
            var totalChunks = Math.Max(1, (int)Math.Ceiling(bytes.LongLength / (double)ChunkSize));
            var session = await _api.InitSharedUploadAsync(grant.Grant, name, totalChunks, ct);

            try
            {
                for (var index = 0; index < totalChunks; index++)
                {
                    var chunkOffset = index * ChunkSize;
                    var chunkLength = Math.Min(ChunkSize, bytes.Length - chunkOffset);
                    var chunk = bytes.AsSpan(chunkOffset, chunkLength).ToArray();
                    var hashHex = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(chunk)).ToLowerInvariant();
                    await _api.UploadSharedChunkAsync(grant.Grant, session.SessionId, index, hashHex, chunk, ct);
                }
            }
            catch
            {
                // A partially-uploaded session left behind holds server resources
                // (and, worse, a stray manifest reference) for no reason once the
                // caller already knows this write failed — abort it rather than
                // leaving cleanup to the grant's TTL.
                await _api.AbortSharedUploadAsync(grant.Grant, session.SessionId, ct);
                throw;
            }

            var complete = await _api.CompleteSharedUploadAsync(grant.Grant, session.SessionId, ct);
            var file = await _api.RecordVersionAsync(Token, grant.FileId, complete.Receipt, ct);

            _logger.LogInformation("MCP tool {Tool} succeeded, {Bytes} bytes, {Chunks} chunks", nameof(write_file), bytes.LongLength, totalChunks);

            return JsonSerializer.Serialize(new { file.Id, file.Name, file.IsFolder, file.SizeBytes, file.ParentId }, JsonOptions);
        }
        finally
        {
            TransferConcurrencyGate.Release();
        }
    }

    [McpServerTool, Description("Create a folder. parentId is a folder id from list_files (omit for the shared root).")]
    public async Task<string> create_folder(string name, Guid? parentId = null, CancellationToken ct = default)
    {
        var folder = await _api.CreateFolderAsync(Token, parentId, name, ct);
        _logger.LogInformation("MCP tool {Tool} succeeded", nameof(create_folder));
        return JsonSerializer.Serialize(new { folder.Id, folder.Name, folder.IsFolder, folder.ParentId }, JsonOptions);
    }

    [McpServerTool, Description("Delete a file or folder by id (moves it to trash). Requires the link to allow deletion; the shared root itself cannot be deleted.")]
    public async Task<string> delete_item(Guid id, CancellationToken ct)
    {
        await _api.DeleteItemAsync(Token, id, ct);
        _logger.LogInformation("MCP tool {Tool} succeeded", nameof(delete_item));
        return "true";
    }

    private static bool TryDecodeStrictUtf8(byte[] bytes, out string text)
    {
        try
        {
            var strictUtf8 = Encoding.GetEncoding(
                "utf-8", EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback);
            text = strictUtf8.GetString(bytes);
            return true;
        }
        catch (DecoderFallbackException)
        {
            text = string.Empty;
            return false;
        }
    }
}
