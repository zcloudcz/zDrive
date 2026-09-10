using Microsoft.EntityFrameworkCore;
using Testcontainers.PostgreSql;
using Xunit;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.Shared.Persistence;

namespace ZDrive.AuthService.Tests.Integration;

/// <summary>
/// Exercises DatabaseMigrationExtensions.MigrateWithBaselineAsync directly
/// against a throwaway Postgres container — the two scenarios plain
/// Migrate() cannot handle on its own (see that class's remarks): aborting
/// loudly instead of guessing when a schema has tables but no migration
/// history, and serializing concurrent migrators racing the same schema.
/// AuthDbContext stands in for any of the six services here; the extension
/// method itself is DbContext-agnostic.
/// </summary>
[Trait("Category", "Integration")]
public sealed class MigrationBaselineTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("zdrive_test")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    public Task InitializeAsync() => _postgres.StartAsync();

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    private AuthDbContext CreateContext() => new(new DbContextOptionsBuilder<AuthDbContext>()
        .UseNpgsql(_postgres.GetConnectionString() + ";Search Path=auth",
            npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "auth"))
        .Options);

    [Fact]
    public async Task MigrateWithBaselineAsync_SchemaFromOldEnsureCreatedWorkaround_ThrowsInsteadOfGuessing()
    {
        // Simulate the old CreateTablesAsync() workaround this PR replaced: it
        // built the schema/tables straight from the current model, with no
        // migration ever recorded. EnsureCreatedAsync() does exactly that.
        //
        // Note this can only prove the "has tables, no history" branch is
        // reached — it cannot exercise the false positive an earlier version
        // of this helper had (baselining a schema that merely had matching
        // table names but was missing a column), because EnsureCreatedAsync()
        // generates DDL from the *current* model, so drift from that model is
        // impossible by construction. That case is exactly why baselining was
        // removed instead of made more precise.
        await using (var oldStyleDb = CreateContext())
        {
            await oldStyleDb.Database.EnsureCreatedAsync();
        }

        await using var db = CreateContext();
        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => db.MigrateWithBaselineAsync("auth"));
        Assert.Contains("no applied migrations recorded", ex.Message);
    }

    [Fact]
    public async Task MigrateWithBaselineAsync_PartiallyMatchingSchema_ThrowsInsteadOfGuessing()
    {
        // Only one of the three tables the model expects — not a full old-style
        // install, not a fresh one either. Guessing here would risk recording
        // migrations as applied against a schema that doesn't actually match.
        await using (var conn = new Npgsql.NpgsqlConnection(_postgres.GetConnectionString()))
        {
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "CREATE SCHEMA auth; CREATE TABLE auth.tenants (id uuid PRIMARY KEY);";
            await cmd.ExecuteNonQueryAsync();
        }

        await using var db = CreateContext();
        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => db.MigrateWithBaselineAsync("auth"));
        Assert.Contains("no applied migrations recorded", ex.Message);
    }

    [Fact]
    public async Task MigrateWithBaselineAsync_TablesWithEmptyHistoryTable_ThrowsInsteadOfReplaying()
    {
        // What a half-finished manual recovery leaves behind: someone created
        // the history table but the INSERT failed (ProductVersion is NOT NULL
        // with no default). Keying the guard on the table's existence rather
        // than on an applied migration would treat this as tracked, skip the
        // abort, and replay the DDL into 42P07 on every start — the exact
        // failure the guard exists to prevent.
        await using (var oldStyleDb = CreateContext())
        {
            await oldStyleDb.Database.EnsureCreatedAsync();
        }

        await using (var conn = new Npgsql.NpgsqlConnection(_postgres.GetConnectionString()))
        {
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText =
                """
                CREATE TABLE auth."__EFMigrationsHistory" (
                    "MigrationId" character varying(150) NOT NULL,
                    "ProductVersion" character varying(32) NOT NULL,
                    CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY ("MigrationId")
                );
                """;
            await cmd.ExecuteNonQueryAsync();
        }

        await using var db = CreateContext();
        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => db.MigrateWithBaselineAsync("auth"));
        Assert.Contains("no applied migrations recorded", ex.Message);
    }

    [Fact]
    public async Task MigrateWithBaselineAsync_ConcurrentReplicas_DoNotRaceTheSameMigration()
    {
        // EF Core 8 takes no lock around Migrate(), so three replicas scaling up
        // from zero (Container Apps min_replicas=0) against a fresh schema would
        // otherwise race each other applying InitialCreate (finding 3). The
        // per-schema advisory lock in MigrateWithBaselineAsync must serialize them.
        var tasks = Enumerable.Range(0, 3)
            .Select(async _ =>
            {
                await using var db = CreateContext();
                await db.MigrateWithBaselineAsync("auth");
            });

        await Task.WhenAll(tasks); // throws if any replica raced and failed

        await using var verifyDb = CreateContext();
        var applied = await verifyDb.Database.GetAppliedMigrationsAsync();
        Assert.Single(applied);
    }
}
