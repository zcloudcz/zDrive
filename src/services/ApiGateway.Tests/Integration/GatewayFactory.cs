using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace ZDrive.ApiGateway.Tests.Integration;

/// <summary>
/// Boots the gateway in Development so it picks up the per-machine dev JWT key
/// pair instead of demanding Jwt:RsaPublicKeyPem from configuration.
/// </summary>
/// <remarks>
/// The environment is set per factory rather than through a process-wide
/// variable, so parallel test classes cannot race each other.
///
/// Nothing here starts the downstream services: these tests are about the
/// gateway's own route table, so an unreachable destination (502) is a
/// meaningful result rather than a broken fixture.
/// </remarks>
public sealed class GatewayFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
    }
}
