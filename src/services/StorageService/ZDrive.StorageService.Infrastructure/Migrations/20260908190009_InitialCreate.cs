using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.StorageService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "storage");

            migrationBuilder.CreateTable(
                name: "blob_chunks",
                schema: "storage",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FileId = table.Column<Guid>(type: "uuid", nullable: false),
                    ChunkHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    ChunkIndex = table.Column<int>(type: "integer", nullable: false),
                    SizeBytes = table.Column<long>(type: "bigint", nullable: false),
                    BlobPath = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_blob_chunks", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "upload_sessions",
                schema: "storage",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    FileId = table.Column<Guid>(type: "uuid", nullable: false),
                    FileName = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    TotalChunks = table.Column<int>(type: "integer", nullable: false),
                    UploadedChunks = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_upload_sessions", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_blob_chunks_FileId",
                schema: "storage",
                table: "blob_chunks",
                column: "FileId");

            migrationBuilder.CreateIndex(
                name: "IX_blob_chunks_FileId_ChunkHash",
                schema: "storage",
                table: "blob_chunks",
                columns: new[] { "FileId", "ChunkHash" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_upload_sessions_FileId",
                schema: "storage",
                table: "upload_sessions",
                column: "FileId");

            migrationBuilder.CreateIndex(
                name: "IX_upload_sessions_TenantId_UserId",
                schema: "storage",
                table: "upload_sessions",
                columns: new[] { "TenantId", "UserId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "blob_chunks",
                schema: "storage");

            migrationBuilder.DropTable(
                name: "upload_sessions",
                schema: "storage");
        }
    }
}
