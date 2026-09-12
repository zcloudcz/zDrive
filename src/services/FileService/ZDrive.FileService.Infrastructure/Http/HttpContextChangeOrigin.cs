using Microsoft.AspNetCore.Http;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Infrastructure.Http;

/// <summary>
/// Reads the originating device from the current request's X-Device-Id
/// header. See IChangeOrigin for why this header exists. Registered as a
/// singleton — IHttpContextAccessor itself wraps an AsyncLocal, so it
/// resolves the correct ambient request without a per-request scope.
/// </summary>
public sealed class HttpContextChangeOrigin : IChangeOrigin
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public HttpContextChangeOrigin(IHttpContextAccessor httpContextAccessor) =>
        _httpContextAccessor = httpContextAccessor;

    public Guid? DeviceId
    {
        get
        {
            var header = _httpContextAccessor.HttpContext?.Request.Headers["X-Device-Id"].FirstOrDefault();
            return Guid.TryParse(header, out var deviceId) ? deviceId : null;
        }
    }
}
