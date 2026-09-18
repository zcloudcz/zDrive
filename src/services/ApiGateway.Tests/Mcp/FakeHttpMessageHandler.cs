using System.Net;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// Records every request and answers via a caller-supplied responder, so
/// ShareLinkApiClient/ShareLinkTools tests can assert on the exact path,
/// headers and body sent to FileService/StorageService without a real
/// network call.
/// </summary>
public sealed class FakeHttpMessageHandler : HttpMessageHandler
{
    private readonly Func<HttpRequestMessage, Task<HttpResponseMessage>> _responder;

    public List<HttpRequestMessage> Requests { get; } = new();

    public FakeHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) =>
        _responder = request => Task.FromResult(responder(request));

    private FakeHttpMessageHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> asyncResponder, bool _) =>
        _responder = asyncResponder;

    /// <summary>
    /// For tests that need the responder to genuinely suspend (e.g. waiting on
    /// a gate) rather than complete synchronously — the sync-Func overload
    /// above wraps its result in Task.FromResult, so a blocking call inside it
    /// would block the calling thread instead of yielding.
    /// </summary>
    public static FakeHttpMessageHandler Async(Func<HttpRequestMessage, Task<HttpResponseMessage>> responder) => new(responder, true);

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        // ShareLinkApiClient disposes each HttpRequestMessage right after
        // awaiting SendAsync, so tests can still read Method/RequestUri/Headers
        // off the recorded instances afterwards, but not Content — read the
        // body inside the responder callback if a test needs it.
        Requests.Add(request);
        return await _responder(request);
    }

    public static HttpResponseMessage Json(HttpStatusCode status, string json) => new(status)
    {
        Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
    };
}
