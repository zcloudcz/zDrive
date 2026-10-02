using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.PhotoService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPhotoIngestPipeline : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "Attempts",
                schema: "photos",
                table: "photos",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "FailureReason",
                schema: "photos",
                table: "photos",
                type: "character varying(1024)",
                maxLength: 1024,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsHidden",
                schema: "photos",
                table: "photos",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTime>(
                name: "LockedUntil",
                schema: "photos",
                table: "photos",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "NextAttemptAt",
                schema: "photos",
                table: "photos",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ProcessedAt",
                schema: "photos",
                table: "photos",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ProcessedManifestHash",
                schema: "photos",
                table: "photos",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SourceManifestHash",
                schema: "photos",
                table: "photos",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "ThumbnailsReady",
                schema: "photos",
                table: "photos",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "ingest_cursors",
                schema: "photos",
                columns: table => new
                {
                    Name = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    LastChangeId = table.Column<long>(type: "bigint", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ingest_cursors", x => x.Name);
                });

            migrationBuilder.CreateIndex(
                name: "IX_photos_ProcessingStatus_NextAttemptAt",
                schema: "photos",
                table: "photos",
                columns: new[] { "ProcessingStatus", "NextAttemptAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ingest_cursors",
                schema: "photos");

            migrationBuilder.DropIndex(
                name: "IX_photos_ProcessingStatus_NextAttemptAt",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "Attempts",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "FailureReason",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "IsHidden",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "LockedUntil",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "NextAttemptAt",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "ProcessedAt",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "ProcessedManifestHash",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "SourceManifestHash",
                schema: "photos",
                table: "photos");

            migrationBuilder.DropColumn(
                name: "ThumbnailsReady",
                schema: "photos",
                table: "photos");
        }
    }
}
