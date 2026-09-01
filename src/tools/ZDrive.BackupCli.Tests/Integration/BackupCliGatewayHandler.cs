namespace ZDrive.BackupCli.Tests.Integration;

/// <summary>
/// Stands in for the real API Gateway (YARP): routes by URL path prefix to
/// whichever in-process WebApplicationFactory client owns that route. Good
/// enough to reproduce the gateway's contract (same paths BackupCli calls)
/// without spinning up YARP itself. Blob SAS URLs bypass this entirely —
/// they point straight at the real Azurite container over a real socket.
/// </summary>
public sealed class BackupCliGatewayHandler(BackupCliEnvironment env) : HttpMessageHandler
{
    private readonly HttpClient _auth = env.AuthFactory.CreateClient();
    private readonly HttpClient _files = env.FileFactory.CreateClient();
    private readonly HttpClient _storage = env.StorageFactory.CreateClient();

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var path = request.RequestUri!.AbsolutePath;
        var target = path switch
        {
            _ when path.StartsWith("/api/v1/auth") || path.StartsWith("/api/v1/users") => _auth,
            _ when path.StartsWith("/api/v1/files") || path.StartsWith("/api/v1/shares") => _files,
            _ when path.StartsWith("/api/v1/storage") => _storage,
            _ => throw new InvalidOperationException($"No fake-gateway route for '{path}'.")
        };

        // An HttpRequestMessage can only ever be sent once via HttpClient —
        // the caller's own HttpClient already "sent" it to reach this
        // handler, so it must be rebuilt before handing it to the target
        // client's TestServer pipeline.
        var forwarded = new HttpRequestMessage(request.Method, request.RequestUri!.PathAndQuery);
        if (request.Content is not null)
        {
            var bytes = await request.Content.ReadAsByteArrayAsync(ct);
            forwarded.Content = new ByteArrayContent(bytes);
            foreach (var header in request.Content.Headers)
                forwarded.Content.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }
        foreach (var header in request.Headers)
            forwarded.Headers.TryAddWithoutValidation(header.Key, header.Value);

        return await target.SendAsync(forwarded, ct);
    }
}
