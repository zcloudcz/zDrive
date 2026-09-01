using System.Text.Json;

namespace ZDrive.BackupCli.Api;

internal static class JsonDefaults
{
    /// <summary>All API envelopes are camelCase (see each service's Program.cs).</summary>
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}
