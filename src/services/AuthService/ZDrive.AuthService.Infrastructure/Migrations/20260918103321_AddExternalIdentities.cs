using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZDrive.AuthService.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddExternalIdentities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "PasswordHash",
                schema: "auth",
                table: "users",
                type: "character varying(512)",
                maxLength: 512,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(512)",
                oldMaxLength: 512);

            migrationBuilder.AddColumn<DateTime>(
                name: "AbsoluteExpiresAt",
                schema: "auth",
                table: "refresh_tokens",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "external_identities",
                schema: "auth",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProviderTenantId = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ObjectId = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now() at time zone 'utc'")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_external_identities", x => x.Id);
                    table.ForeignKey(
                        name: "FK_external_identities_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "auth",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_external_identities_ProviderTenantId_ObjectId",
                schema: "auth",
                table: "external_identities",
                columns: new[] { "ProviderTenantId", "ObjectId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_external_identities_UserId",
                schema: "auth",
                table: "external_identities",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "external_identities",
                schema: "auth");

            migrationBuilder.DropColumn(
                name: "AbsoluteExpiresAt",
                schema: "auth",
                table: "refresh_tokens");

            migrationBuilder.AlterColumn<string>(
                name: "PasswordHash",
                schema: "auth",
                table: "users",
                type: "character varying(512)",
                maxLength: 512,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "character varying(512)",
                oldMaxLength: 512,
                oldNullable: true);
        }
    }
}
