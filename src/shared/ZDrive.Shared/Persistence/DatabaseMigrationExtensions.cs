using System.Data.Common;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace ZDrive.Shared.Persistence;

/// <summary>
/// Startup migration helper shared by every service's own single-schema
/// PostgreSQL database (see each service's DependencyInjection.cs, which
/// scopes <c>MigrationsHistoryTable</c> to that service's schema).
///
/// Wraps <see cref="RelationalDatabaseFacadeExtensions.MigrateAsync"/> with
/// two things plain <c>Migrate()</c> does not handle on its own:
///
///  - Installations created by the old EnsureCreated-based workaround (before
///    this service had real EF migrations) have every table but no
///    __EFMigrationsHistory row. Migrate() would see the migration as
///    pending and replay its CREATE TABLE statements against a schema that
///    already has them, crashing with 42P07. <see cref="BaselineIfAlreadyPopulatedAsync"/>
///    detects that case and records the pending migrations as already
///    applied instead of replaying their DDL — but only when every table
///    the current model expects is already present; a partial match aborts
///    instead of guessing at a schema that might just be unrelated.
///  - EF Core 8 takes no lock around Migrate() (that lands in EF Core 9), so
///    concurrent replicas scaling up from zero can race each other applying
///    the same migration. A Postgres advisory lock scoped to this schema
///    serializes them; the loser just waits instead of throwing.
/// </summary>
public static class DatabaseMigrationExtensions
{
    /// <summary>
    /// Migrates <paramref name="db"/>'s schema, baselining an old
    /// EnsureCreated-created install first if needed. See class remarks.
    /// </summary>
    /// <param name="schema">The Postgres schema this context owns (matches its MigrationsHistoryTable schema).</param>
    public static async Task MigrateWithBaselineAsync(this DbContext db, string schema, ILogger? logger = null)
    {
        var database = db.Database;
        await database.OpenConnectionAsync();
        try
        {
            // Serializes concurrent migrators for this schema (scale-from-zero
            // burst); released automatically when the connection closes below,
            // even if this method throws.
            await AcquireSchemaLockAsync(database.GetDbConnection(), schema);

            if (!await HistoryTableExistsAsync(database.GetDbConnection(), schema))
            {
                await BaselineIfAlreadyPopulatedAsync(db, schema, logger);
            }

            await database.MigrateAsync();
        }
        finally
        {
            await database.CloseConnectionAsync();
        }
    }

    /// <remarks>
    /// Waiting for this lock takes as long as the migration the holder is
    /// running, which can exceed a normal command timeout — the default 30s
    /// made a three-replica burst fail with "Timeout during reading attempt"
    /// instead of queueing. CommandTimeout = 0 disables the client-side
    /// timeout for the wait only; every later statement keeps the configured
    /// one, so a genuinely stuck migration still surfaces rather than hanging
    /// the whole startup forever.
    /// </remarks>
    private static async Task AcquireSchemaLockAsync(DbConnection connection, string schema)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText = "SELECT pg_advisory_lock(hashtext(@schema)::bigint)";
        cmd.CommandTimeout = 0;
        AddParameter(cmd, "schema", schema);
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task<bool> HistoryTableExistsAsync(DbConnection connection, string schema)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText =
            "SELECT 1 FROM information_schema.tables WHERE table_schema = @schema AND table_name = '__EFMigrationsHistory'";
        AddParameter(cmd, "schema", schema);
        return await cmd.ExecuteScalarAsync() is not null;
    }

    private static async Task BaselineIfAlreadyPopulatedAsync(DbContext db, string schema, ILogger? logger)
    {
        var expectedTables = db.Model.GetEntityTypes()
            .Select(e => e.GetTableName())
            .Where(t => t is not null)
            .Distinct()
            .ToList();

        var connection = db.Database.GetDbConnection();
        var existingTables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var cmd = connection.CreateCommand())
        {
            cmd.CommandText = "SELECT table_name FROM information_schema.tables WHERE table_schema = @schema";
            AddParameter(cmd, "schema", schema);
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                existingTables.Add(reader.GetString(0));
            }
        }

        var matchCount = expectedTables.Count(t => existingTables.Contains(t!));
        if (matchCount == 0)
        {
            return; // Fresh install — MigrateAsync() below creates the schema and tables.
        }

        if (matchCount != expectedTables.Count)
        {
            throw new InvalidOperationException(
                $"Schema '{schema}' has {matchCount}/{expectedTables.Count} of the tables the current model " +
                "expects, but no __EFMigrationsHistory table. This looks like a partially-created or unrelated " +
                "schema rather than a full install from the old EnsureCreated-based workaround — refusing to " +
                "guess. Reconcile the schema manually, then retry.");
        }

        // Every table the current model expects is already there — this is the
        // old workaround's install. Record the pending migrations as applied
        // instead of letting MigrateAsync() replay their DDL against tables
        // that already exist.
        logger?.LogWarning(
            "Schema '{Schema}' has all expected tables but no migration history — baselining as an existing " +
            "install instead of replaying migrations.", schema);

        var pendingMigrations = await db.Database.GetPendingMigrationsAsync();
        var productVersion = typeof(DbContext).Assembly.GetName().Version!.ToString(3);

        using (var createCmd = connection.CreateCommand())
        {
            createCmd.CommandText =
                $"CREATE TABLE IF NOT EXISTS \"{schema}\".\"__EFMigrationsHistory\" (" +
                "\"MigrationId\" character varying(150) NOT NULL, " +
                "\"ProductVersion\" character varying(32) NOT NULL, " +
                "CONSTRAINT \"PK___EFMigrationsHistory\" PRIMARY KEY (\"MigrationId\"))";
            await createCmd.ExecuteNonQueryAsync();
        }

        foreach (var migrationId in pendingMigrations)
        {
            using var insertCmd = connection.CreateCommand();
            insertCmd.CommandText =
                $"INSERT INTO \"{schema}\".\"__EFMigrationsHistory\" (\"MigrationId\", \"ProductVersion\") " +
                "VALUES (@id, @version) ON CONFLICT DO NOTHING";
            AddParameter(insertCmd, "id", migrationId);
            AddParameter(insertCmd, "version", productVersion);
            await insertCmd.ExecuteNonQueryAsync();
        }
    }

    private static void AddParameter(DbCommand cmd, string name, string value)
    {
        var p = cmd.CreateParameter();
        p.ParameterName = name;
        p.Value = value;
        cmd.Parameters.Add(p);
    }
}
