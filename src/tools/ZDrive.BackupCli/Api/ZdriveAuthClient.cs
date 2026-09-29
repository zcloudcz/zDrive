using System.Net.Http.Json;

namespace ZDrive.BackupCli.Api;

/// <summary>
/// Owns login/refresh against AuthService. Runs on its own HttpClient (no
/// bearer-token handler attached) so refreshing never recurses into itself —
/// same reasoning as the Flutter client's AuthInterceptor.
/// </summary>
public sealed class ZdriveAuthClient(HttpClient http)
{
    public string? AccessToken { get; private set; }
    private string? _refreshToken;

    public async Task LoginAsync(string email, string password, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(
            "auth/login", new { email, password }, JsonDefaults.Options, ct);

        if (!response.IsSuccessStatusCode)
        {
            // Never echo the request body — it contains the password.
            throw new ZdriveApiException(
                $"Login failed ({(int)response.StatusCode} {response.StatusCode}): invalid credentials or unreachable API.");
        }

        var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<LoginResult>>(JsonDefaults.Options, ct)
            ?? throw new ZdriveApiException("Login failed: empty response from API.");
        if (!envelope.Success || envelope.Data is null)
            throw new ZdriveApiException($"Login failed: {envelope.Error?.Message ?? "unknown error"}.");

        if (envelope.Data.TwoFactorRequired)
        {
            throw new ZdriveApiException(
                "Login failed: this account has two-factor authentication enabled, which BackupCli does not support. " +
                "Use an account without 2FA for backups.");
        }

        if (envelope.Data.AccessToken is null || envelope.Data.RefreshToken is null)
            throw new ZdriveApiException("Login failed: the API returned no tokens.");

        AccessToken = envelope.Data.AccessToken;
        _refreshToken = envelope.Data.RefreshToken;
    }

    public async Task<bool> TryRefreshAsync(CancellationToken ct)
    {
        if (_refreshToken is null)
            return false;

        using var response = await http.PostAsJsonAsync(
            "auth/refresh", new { refreshToken = _refreshToken }, JsonDefaults.Options, ct);
        if (!response.IsSuccessStatusCode)
            return false;

        var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<AuthTokens>>(JsonDefaults.Options, ct);
        if (envelope is not { Success: true, Data: not null })
            return false;

        AccessToken = envelope.Data.AccessToken;
        _refreshToken = envelope.Data.RefreshToken;
        return true;
    }
}
