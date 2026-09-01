using System.Text.Json;
using ZDrive.BackupCli.Api;
using ZDrive.BackupCli.Backup;

var stdout = Console.Out;
var stderr = Console.Error;

string? localDir = null;
string? destPath = null;
for (var i = 0; i < args.Length; i++)
{
    if (args[i] == "--dest")
    {
        if (i + 1 >= args.Length)
        {
            stderr.WriteLine("--dest requires a value.");
            return 1;
        }
        destPath = args[++i];
    }
    else if (localDir is null)
    {
        localDir = args[i];
    }
    else
    {
        stderr.WriteLine($"Unexpected argument: {args[i]}");
        return 1;
    }
}

if (localDir is null)
{
    stderr.WriteLine("Usage: zdrive-backup <local-directory> [--dest <remote-folder-path>]");
    stderr.WriteLine("Required env vars: ZDRIVE_API_URL, ZDRIVE_USER, ZDRIVE_PASSWORD");
    return 1;
}

if (!Directory.Exists(localDir))
{
    stderr.WriteLine($"Local directory not found: {localDir}");
    return 1;
}

var apiUrl = Environment.GetEnvironmentVariable("ZDRIVE_API_URL");
var user = Environment.GetEnvironmentVariable("ZDRIVE_USER");
var password = Environment.GetEnvironmentVariable("ZDRIVE_PASSWORD");
if (string.IsNullOrWhiteSpace(apiUrl) || string.IsNullOrWhiteSpace(user) || string.IsNullOrWhiteSpace(password))
{
    stderr.WriteLine("Missing required env vars: ZDRIVE_API_URL, ZDRIVE_USER, ZDRIVE_PASSWORD must all be set.");
    return 1;
}

Uri baseAddress;
try
{
    baseAddress = new Uri(apiUrl.TrimEnd('/') + "/");
    if (baseAddress.Scheme is not ("http" or "https"))
        throw new UriFormatException("ZDRIVE_API_URL must be an http(s) URL.");
}
catch (UriFormatException ex)
{
    stderr.WriteLine($"Invalid ZDRIVE_API_URL '{apiUrl}': {ex.Message}");
    return 1;
}

// Login sends the password in the request body — over plain http that's
// readable to anyone on the network path. Allow it unencrypted only to
// localhost (dev/test); anywhere else requires an explicit opt-in.
if (InsecureHttpPolicy.IsBlocked(baseAddress))
{
    stderr.WriteLine(
        $"Refusing plain http:// to non-localhost host '{baseAddress.Host}': credentials would be sent unencrypted. " +
        "Set ZDRIVE_ALLOW_INSECURE=1 to override.");
    return 1;
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true; // let the in-flight file finish reporting, then exit via the caught OperationCanceledException below
    stderr.WriteLine("Interrupted — stopping after the current file.");
    cts.Cancel();
};

// Bare client for login/refresh only — never carries the bearer token, so a
// refresh call can't recurse into AuthTokenHandler (see ZdriveAuthClient).
using var authHttp = new HttpClient { BaseAddress = baseAddress };
var authClient = new ZdriveAuthClient(authHttp);

using var apiHttp = new HttpClient(new AuthTokenHandler(authClient) { InnerHandler = new HttpClientHandler() })
{
    BaseAddress = baseAddress
};
// SAS download URLs point at blob storage directly and must never carry our
// API bearer token — see ZdriveApiClient.TryGetManifestAsync.
using var blobHttp = new HttpClient();

try
{
    await authClient.LoginAsync(user, password, cts.Token);
}
catch (ZdriveApiException ex)
{
    stderr.WriteLine(ex.Message); // never contains the password
    return 1;
}
catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
{
    // DNS/TLS/connection failures during login — never contains the password.
    stderr.WriteLine($"Could not reach {apiUrl}: {ex.Message}");
    return 1;
}
catch (JsonException ex)
{
    // Login got a non-JSON response (e.g. a proxy error page) — never contains the password.
    stderr.WriteLine($"Login failed: unexpected response from {apiUrl} ({ex.Message}).");
    return 1;
}

var api = new ZdriveApiClient(apiHttp, blobHttp);
var runner = new BackupRunner(api, stdout, stderr);

try
{
    return await runner.RunAsync(localDir, destPath, cts.Token);
}
catch (OperationCanceledException)
{
    stderr.WriteLine("Backup interrupted; re-run to resume.");
    return 1;
}
catch (ZdriveApiException ex)
{
    stderr.WriteLine(ex.Message);
    return 1;
}
catch (Exception ex)
{
    // Last-resort net: an unexpected failure (network, I/O, ...) should still
    // exit non-zero with a plain message on stderr, never a raw stack trace,
    // so a cron job's failure alert stays readable.
    stderr.WriteLine($"Backup failed: {ex.Message}");
    return 1;
}
