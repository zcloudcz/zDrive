namespace ZDrive.ApiGateway.Mcp;

/// <summary>
/// Bound from the "Mcp" configuration section. MaxInlineBytes caps both
/// read_file and write_file: MCP carries content inside the JSON-RPC message,
/// which the gateway holds fully in memory, so anything bigger has to go
/// through the REST API instead.
/// </summary>
public sealed class McpOptions
{
    public long MaxInlineBytes { get; set; } = 26_214_400; // 25 MiB
}
