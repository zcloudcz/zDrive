namespace ZDrive.FileService.Application.Interfaces;

/// <summary>
/// The device that originated the current request, if any. The desktop sync
/// client tags its own writes with the X-Device-Id header so that its own
/// later pull of the change feed does not download its own writes back —
/// every other client (web, the app's file browser, BackupCli) sends no
/// header, so every device, including the one that made the change, applies
/// it. Abstracted out of Application/Domain so FileChangeInterceptor has no
/// direct dependency on ASP.NET Core; outside an HTTP request this is null.
/// </summary>
public interface IChangeOrigin
{
    Guid? DeviceId { get; }
}
