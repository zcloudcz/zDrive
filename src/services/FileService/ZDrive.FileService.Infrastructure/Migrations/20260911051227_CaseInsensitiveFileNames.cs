using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.FileService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class CaseInsensitiveFileNames : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_file_nodes_tenant_id_user_id_parent_id_name",
                schema: "files",
                table: "file_nodes");

            migrationBuilder.AddColumn<string>(
                name: "name_normalized",
                schema: "files",
                table: "file_nodes",
                type: "character varying(512)",
                maxLength: 512,
                nullable: true,
                computedColumnSql: "lower(name)",
                stored: true);

            // A pre-existing installation may already hold two active
            // siblings whose names differ only by case (e.g. "Photos" and
            // "photos") — legal under the old case-sensitive unique index,
            // illegal under the one below. Building the index straight into
            // that data would abort with a bare Postgres "could not create
            // unique index" error and no indication of which rows are at
            // fault, and the service would then crash-loop on every future
            // startup with the same unhelpful message (see CLAUDE.md,
            // "Recovering a database..." — PR #10 already taught this repo
            // not to ship a migration that fails silently against real
            // data). This guard fails the same way, but names the exact
            // tenant/user/parent groups that collide, so whoever hits it
            // knows which rows to rename or delete before retrying. It does
            // not rename anything automatically: nothing here knows which of
            // the two names is the one users and existing shares expect to
            // keep.
            migrationBuilder.Sql("""
                DO $$
                DECLARE
                    v_offenders text;
                BEGIN
                    SELECT string_agg(
                        format('tenant=%s user=%s parent=%s name=%L (%s rows)',
                            tenant_id, user_id, coalesce(parent_id::text, '<root>'), name, cnt),
                        E'\n' ORDER BY tenant_id, user_id
                    )
                    INTO v_offenders
                    FROM (
                        SELECT tenant_id, user_id, parent_id, lower(name) AS name, count(*) AS cnt
                        FROM "files"."file_nodes"
                        WHERE is_deleted = false
                        GROUP BY tenant_id, user_id, parent_id, lower(name)
                        HAVING count(*) > 1
                    ) collisions;

                    IF v_offenders IS NOT NULL THEN
                        RAISE EXCEPTION E'Migration CaseInsensitiveFileNames cannot proceed: the following siblings collide case-insensitively and must be renamed or deleted first:\n%', v_offenders;
                    END IF;
                END $$;
                """);

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_tenant_id_user_id_parent_id_name_normalized",
                schema: "files",
                table: "file_nodes",
                columns: new[] { "tenant_id", "user_id", "parent_id", "name_normalized" },
                unique: true,
                filter: "is_deleted = false")
                .Annotation("Npgsql:NullsDistinct", false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_file_nodes_tenant_id_user_id_parent_id_name_normalized",
                schema: "files",
                table: "file_nodes");

            migrationBuilder.DropColumn(
                name: "name_normalized",
                schema: "files",
                table: "file_nodes");

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_tenant_id_user_id_parent_id_name",
                schema: "files",
                table: "file_nodes",
                columns: new[] { "tenant_id", "user_id", "parent_id", "name" },
                unique: true,
                filter: "is_deleted = false");
        }
    }
}
