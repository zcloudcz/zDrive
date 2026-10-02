using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.AuthService.Infrastructure.Persistence;

namespace ZDrive.AuthService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class ModuleSchemaTests : IClassFixture<AuthServiceFactory>
{
    private readonly AuthServiceFactory _factory;

    public ModuleSchemaTests(AuthServiceFactory factory) => _factory = factory;

    [Fact]
    public async Task Startup_SingleZDriveDbConnectionString_EachModuleMigratesIntoItsOwnSchema()
    {
        _factory.CreateClient(); // starts the host, which migrates all five contexts

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        var tables = await db.Database.SqlQueryRaw<string>(
            """
            SELECT table_schema || '.' || table_name AS "Value" FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
            """).ToListAsync();

        // The connection string names no schema: every table must still land
        // in its module's schema, which only holds while each model/migration
        // names its schema itself. Nothing may fall through to public.
        tables.Should().Contain(["storage.blob_chunks", "sync.devices", "photos.photos", "files.file_nodes", "auth.users"]);
        tables.Should().NotContain(t => t.StartsWith("public."));
    }
}
