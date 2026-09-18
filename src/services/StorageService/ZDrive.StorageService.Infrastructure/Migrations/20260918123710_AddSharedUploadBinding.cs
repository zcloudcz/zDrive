using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.StorageService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSharedUploadBinding : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "MaxBytes",
                schema: "storage",
                table: "upload_sessions",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "ReceivedBytes",
                schema: "storage",
                table: "upload_sessions",
                type: "bigint",
                nullable: false,
                defaultValue: 0L);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MaxBytes",
                schema: "storage",
                table: "upload_sessions");

            migrationBuilder.DropColumn(
                name: "ReceivedBytes",
                schema: "storage",
                table: "upload_sessions");
        }
    }
}
