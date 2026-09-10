using System.Data.Common;
using Microsoft.EntityFrameworkCore;

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
///    already has them, crashing with 42P07. This helper detects that
///    case — any table other than the history table present in a schema
///    with no applied migration recorded — and
///    aborts with an error naming the manual recovery step, instead of
///    guessing whether the schema actually matches the current model. An
///    earlier version of this helper tried to guess from the set of table
///    names alone and baseline automatically; that could mark a migration
///    as applied against a schema that was actually missing one of its
///    columns, corrupting migration state permanently (no later
///    `dotnet ef database update` revisits a migration EF already believes
///    ran). Silent corruption is worse than a loud startup failure, so this
///    helper no longer guesses at all.
///  - EF Core 8 takes no lock around Migrate() (that lands in EF Core 9), so
///    concurrent replicas scaling up from zero can race each other applying
///    the same migration. A Postgres advisory lock scoped to this schema
///    serializes them; the loser just waits instead of throwing.
/// </summary>
public static class DatabaseMigrationExtensions
{
    /// <summary>
    /// Migrates <paramref name="db"/>'s schema, aborting instead of guessing
    /// if the schema looks like an old EnsureCreated-created install. See
    /// class remarks.
    /// </summary>
    /// <param name="schema">The Postgres schema this context owns (matches its MigrationsHistoryTable schema).</param>
    public static async Task MigrateWithBaselineAsync(this DbContext db, string schema)
    {
        var database = db.Database;
        await database.OpenConnectionAsync();
        var locked = false;
        try
        {
            // Serializes concurrent migrators for this schema (scale-from-zero
            // burst).
            await AcquireSchemaLockAsync(database.GetDbConnection(), schema);
            locked = true;

            // Keyed on applied migrations, not on the history table existing.
            // An empty history table is what a half-finished manual recovery
            // leaves behind, and treating that as "tracked" would skip the
            // guard and replay the DDL into 42P07 — the exact failure the
            // guard exists to prevent.
            if (!await HasAppliedMigrationsAsync(database.GetDbConnection(), schema))
            {
                await AbortIfSchemaAlreadyHasTablesAsync(database.GetDbConnection(), schema);
            }

            await database.MigrateAsync();
        }
        finally
        {
            // The lock MUST be released explicitly. It is session-scoped, and
            // CloseConnectionAsync below only returns the connection to
            // Npgsql's pool — the Postgres session survives and keeps holding
            // it. Relying on the close alone left the lock held until the pool
            // pruned the physical connection (ConnectionIdleLifetime, 300s by
            // default), which turned the three-replica test from a 31s failure
            // into a 15-minute pass.
            //
            // Nested try/finally: if the migration above already threw and
            // the unlock below also throws (e.g. a degraded connection), the
            // unlock failure must not stop CloseConnectionAsync from running.
            try
            {
                if (locked)
                {
                    await ReleaseSchemaLockAsync(database.GetDbConnection(), schema);
                }
            }
            finally
            {
                await database.CloseConnectionAsync();
            }
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

    private static async Task ReleaseSchemaLockAsync(DbConnection connection, string schema)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText = "SELECT pg_advisory_unlock(hashtext(@schema)::bigint)";
        AddParameter(cmd, "schema", schema);
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task<bool> HasAppliedMigrationsAsync(DbConnection connection, string schema)
    {
        using (var exists = connection.CreateCommand())
        {
            exists.CommandText =
                "SELECT 1 FROM information_schema.tables WHERE table_schema = @schema AND table_name = '__EFMigrationsHistory'";
            AddParameter(exists, "schema", schema);
            if (await exists.ExecuteScalarAsync() is null)
            {
                return false;
            }
        }

        using var rows = connection.CreateCommand();
        // Identifiers cannot be parameterised. `schema` is an internal
        // constant supplied by each service, never user input; the quote
        // doubling is belt-and-braces.
        rows.CommandText = $"SELECT 1 FROM \"{schema.Replace("\"", "\"\"")}\".\"__EFMigrationsHistory\" LIMIT 1";
        return await rows.ExecuteScalarAsync() is not null;
    }

    private static async Task AbortIfSchemaAlreadyHasTablesAsync(DbConnection connection, string schema)
    {
        using var cmd = connection.CreateCommand();
        // Excludes the history table itself: an empty one alongside no other
        // tables is not an old install, and must still migrate normally.
        cmd.CommandText =
            "SELECT 1 FROM information_schema.tables WHERE table_schema = @schema " +
            "AND table_name <> '__EFMigrationsHistory' LIMIT 1";
        AddParameter(cmd, "schema", schema);
        if (await cmd.ExecuteScalarAsync() is null)
        {
            return; // Fresh install — MigrateAsync() below creates the schema and tables.
        }

        throw new InvalidOperationException(
            $"Schema '{schema}' has tables but no applied migrations recorded. This could be an install from " +
            "the old EnsureCreated-based workaround, a partially-created schema, or an unrelated schema that " +
            "happens to share table names — there is no reliable way to tell without inspecting it by hand, so " +
            "refusing to guess and risk marking a migration as applied when the schema does not actually match " +
            "it. For a throwaway dev database, drop the Postgres volume (see docker-compose.yml) and let this " +
            "service recreate the schema from scratch. For a real database, follow \"Recovering a database from " +
            "before EF migrations existed\" in CLAUDE.md — it has the exact DDL, because creating the history " +
            "table without also inserting the migration row leaves this check passing and the next start " +
            "replaying the DDL.");
    }

    private static void AddParameter(DbCommand cmd, string name, string value)
    {
        var p = cmd.CreateParameter();
        p.ParameterName = name;
        p.Value = value;
        cmd.Parameters.Add(p);
    }
}
