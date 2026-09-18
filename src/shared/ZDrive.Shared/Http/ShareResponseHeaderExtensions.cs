using Microsoft.AspNetCore.Http;

namespace ZDrive.Shared.Http;

/// <summary>
/// Response headers for public-share endpoints whose authorization is
/// carried in a header (X-Share-Grant) or an unguessable path token rather
/// than a cookie a shared cache would strip. The URL alone is constant —
/// only the header/token differs between visitors — so without
/// Cache-Control: private, no-store a cache sitting in front of the gateway
/// could replay one visitor's response (manifest bytes, a download grant, a
/// shared folder listing) to a different caller who reused the same URL
/// with no grant of their own. Vary: X-Share-Grant additionally tells any
/// cache that DOES key on headers that two requests to the same URL with
/// different grants are different responses.
///
/// Callers set this on HttpContext.Response directly, before anything that
/// can throw, so it lands on error responses (404s) too — an exception
/// unwinds past any result/action filter, but a header already written to
/// Response survives ExceptionHandlingMiddleware, which only sets
/// ContentType/StatusCode and writes the body.
/// </summary>
public static class ShareResponseHeaderExtensions
{
    public static void SetPublicShareCacheHeaders(this HttpResponse response)
    {
        response.Headers.CacheControl = "private, no-store";
        response.Headers.Vary = "X-Share-Grant";
    }
}
