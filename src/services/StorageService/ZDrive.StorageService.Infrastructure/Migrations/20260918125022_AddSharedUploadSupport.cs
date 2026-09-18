using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.StorageService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSharedUploadSupport : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ChunkSizesJson",
                schema: "storage",
                table: "upload_sessions",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsShared",
                schema: "storage",
                table: "upload_sessions",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<long>(
                name: "MaxBytes",
                schema: "storage",
                table: "upload_sessions",
                type: "bigint",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_upload_sessions_TenantId_UserId_IsShared_CreatedAt",
                schema: "storage",
                table: "upload_sessions",
                columns: new[] { "TenantId", "UserId", "IsShared", "CreatedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_upload_sessions_TenantId_UserId_IsShared_CreatedAt",
                schema: "storage",
                table: "upload_sessions");

            migrationBuilder.DropColumn(
                name: "ChunkSizesJson",
                schema: "storage",
                table: "upload_sessions");

            migrationBuilder.DropColumn(
                name: "IsShared",
                schema: "storage",
                table: "upload_sessions");

            migrationBuilder.DropColumn(
                name: "MaxBytes",
                schema: "storage",
                table: "upload_sessions");
        }
    }
}
