using System;
using Microsoft.EntityFrameworkCore.Migrations;
using NpgsqlTypes;

#nullable disable

namespace ZDrive.FileService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "files");

            migrationBuilder.CreateTable(
                name: "file_nodes",
                schema: "files",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false),
                    parent_id = table.Column<Guid>(type: "uuid", nullable: true),
                    name = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    is_folder = table.Column<bool>(type: "boolean", nullable: false),
                    size_bytes = table.Column<long>(type: "bigint", nullable: true),
                    mime_type = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    blob_path = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    manifest_hash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    deleted_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'"),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'"),
                    name_tsv = table.Column<NpgsqlTsVector>(type: "tsvector", nullable: true, computedColumnSql: "to_tsvector('simple', name)", stored: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_file_nodes", x => x.id);
                    table.ForeignKey(
                        name: "fk_file_nodes_file_nodes_parent_id",
                        column: x => x.parent_id,
                        principalSchema: "files",
                        principalTable: "file_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "file_versions",
                schema: "files",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    file_id = table.Column<Guid>(type: "uuid", nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    blob_version_id = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    size_bytes = table.Column<long>(type: "bigint", nullable: false),
                    manifest_hash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    comment = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_file_versions", x => x.id);
                    table.ForeignKey(
                        name: "fk_file_versions_file_nodes_file_id",
                        column: x => x.file_id,
                        principalSchema: "files",
                        principalTable: "file_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "shares",
                schema: "files",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    file_id = table.Column<Guid>(type: "uuid", nullable: false),
                    shared_by = table.Column<Guid>(type: "uuid", nullable: false),
                    shared_with = table.Column<Guid>(type: "uuid", nullable: true),
                    permission = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    link_token = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    password_hash = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    expires_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_shares", x => x.id);
                    table.ForeignKey(
                        name: "fk_shares_file_nodes_file_id",
                        column: x => x.file_id,
                        principalSchema: "files",
                        principalTable: "file_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_is_deleted",
                schema: "files",
                table: "file_nodes",
                column: "is_deleted");

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_name_tsv",
                schema: "files",
                table: "file_nodes",
                column: "name_tsv")
                .Annotation("Npgsql:IndexMethod", "GIN");

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_parent_id",
                schema: "files",
                table: "file_nodes",
                column: "parent_id");

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_tenant_id_user_id",
                schema: "files",
                table: "file_nodes",
                columns: new[] { "tenant_id", "user_id" });

            migrationBuilder.CreateIndex(
                name: "ix_file_nodes_tenant_id_user_id_parent_id_name",
                schema: "files",
                table: "file_nodes",
                columns: new[] { "tenant_id", "user_id", "parent_id", "name" },
                unique: true,
                filter: "is_deleted = false");

            migrationBuilder.CreateIndex(
                name: "ix_file_versions_file_id_version_number",
                schema: "files",
                table: "file_versions",
                columns: new[] { "file_id", "version_number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_shares_file_id",
                schema: "files",
                table: "shares",
                column: "file_id");

            migrationBuilder.CreateIndex(
                name: "ix_shares_link_token",
                schema: "files",
                table: "shares",
                column: "link_token",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "file_versions",
                schema: "files");

            migrationBuilder.DropTable(
                name: "shares",
                schema: "files");

            migrationBuilder.DropTable(
                name: "file_nodes",
                schema: "files");
        }
    }
}
