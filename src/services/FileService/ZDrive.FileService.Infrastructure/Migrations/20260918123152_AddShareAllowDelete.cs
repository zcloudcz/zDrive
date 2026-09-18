using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.FileService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddShareAllowDelete : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "allow_delete",
                schema: "files",
                table: "shares",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "allow_delete",
                schema: "files",
                table: "shares");
        }
    }
}
