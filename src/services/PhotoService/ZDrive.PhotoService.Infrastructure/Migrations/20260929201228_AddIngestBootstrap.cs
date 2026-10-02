using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.PhotoService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddIngestBootstrap : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "BootstrapCompletedAt",
                schema: "photos",
                table: "ingest_cursors",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "BootstrapHead",
                schema: "photos",
                table: "ingest_cursors",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "BootstrapLastNodeId",
                schema: "photos",
                table: "ingest_cursors",
                type: "uuid",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "BootstrapCompletedAt",
                schema: "photos",
                table: "ingest_cursors");

            migrationBuilder.DropColumn(
                name: "BootstrapHead",
                schema: "photos",
                table: "ingest_cursors");

            migrationBuilder.DropColumn(
                name: "BootstrapLastNodeId",
                schema: "photos",
                table: "ingest_cursors");
        }
    }
}
