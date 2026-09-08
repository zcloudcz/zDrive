using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.SyncService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "sync");

            migrationBuilder.CreateSequence(
                name: "sync_event_id_seq",
                schema: "sync",
                incrementBy: 10);

            migrationBuilder.CreateTable(
                name: "devices",
                schema: "sync",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    Platform = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    SyncCursor = table.Column<long>(type: "bigint", nullable: false),
                    LastSyncAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_devices", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "sync_conflicts",
                schema: "sync",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    FileId = table.Column<Guid>(type: "uuid", nullable: false),
                    LocalDeviceId = table.Column<Guid>(type: "uuid", nullable: false),
                    RemoteDeviceId = table.Column<Guid>(type: "uuid", nullable: false),
                    LocalVersion = table.Column<long>(type: "bigint", nullable: false),
                    RemoteVersion = table.Column<long>(type: "bigint", nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'"),
                    ResolvedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_sync_conflicts", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "sync_events",
                schema: "sync",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    DeviceId = table.Column<Guid>(type: "uuid", nullable: false),
                    FileId = table.Column<Guid>(type: "uuid", nullable: false),
                    EventType = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Metadata = table.Column<string>(type: "jsonb", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_sync_events", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_devices_UserId",
                schema: "sync",
                table: "devices",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_sync_conflicts_FileId",
                schema: "sync",
                table: "sync_conflicts",
                column: "FileId");

            migrationBuilder.CreateIndex(
                name: "IX_sync_conflicts_UserId",
                schema: "sync",
                table: "sync_conflicts",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_sync_events_DeviceId",
                schema: "sync",
                table: "sync_events",
                column: "DeviceId");

            migrationBuilder.CreateIndex(
                name: "IX_sync_events_FileId",
                schema: "sync",
                table: "sync_events",
                column: "FileId");

            migrationBuilder.CreateIndex(
                name: "IX_sync_events_UserId_Id",
                schema: "sync",
                table: "sync_events",
                columns: new[] { "UserId", "Id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "devices",
                schema: "sync");

            migrationBuilder.DropTable(
                name: "sync_conflicts",
                schema: "sync");

            migrationBuilder.DropTable(
                name: "sync_events",
                schema: "sync");

            migrationBuilder.DropSequence(
                name: "sync_event_id_seq",
                schema: "sync");
        }
    }
}
