# PostgreSQL Flexible Server (Burstable B1ms) shared by all services.
# Each service gets its own schema in the same "zdrive" database — see
# ConnectionStrings:{X}Db entries in each service's appsettings.json
# ("Search Path=<schema>"). No per-service DB user; all services connect
# as the same admin login, matching the local dev setup.
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  version    = "16"
  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768

  administrator_login    = "zdrive_admin"
  administrator_password = var.admin_password

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
}

resource "azurerm_postgresql_flexible_server_database" "zdrive" {
  name      = "zdrive"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Container Apps run without VNet integration in the test environment, so
# Postgres is reachable over its public endpoint. This rule is Azure's
# documented way to allow only Azure-hosted resources (0.0.0.0-0.0.0.0),
# not the public internet at large.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
