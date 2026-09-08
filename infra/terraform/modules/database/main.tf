variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

variable "subnet_id" {
  description = "Delegated subnet ID for PostgreSQL Flexible Server"
  type        = string
}

variable "administrator_password" {
  description = "PostgreSQL administrator password. Supply from Key Vault or a CI secret — never a tfvars file in the repo."
  type        = string
  sensitive   = true
  # No default on purpose: a placeholder default is a known password that
  # reaches a real server the first time someone runs apply without noticing.
}

resource "azurerm_resource_group" "database" {
  name     = "rg-${var.prefix}-${var.environment}-db"
  location = var.location
}

# Private DNS zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.prefix}-${var.environment}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.database.name
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-${var.prefix}-${var.environment}"
  resource_group_name = azurerm_resource_group.database.name
  location            = azurerm_resource_group.database.location

  version             = "16"
  sku_name            = var.environment == "production" ? "GP_Standard_D4s_v3" : "B_Standard_B2s"
  storage_mb          = var.environment == "production" ? 131072 : 32768
  delegated_subnet_id = var.subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  zone                = "1"

  administrator_login    = "zdrive_admin"
  administrator_password = var.administrator_password

  backup_retention_days        = var.environment == "production" ? 35 : 7
  geo_redundant_backup_enabled = var.environment == "production" ? true : false
}

# Database
resource "azurerm_postgresql_flexible_server_database" "zdrive" {
  name      = "zdrive"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

output "connection_string" {
  description = "PostgreSQL connection string"
  value       = "Host=${azurerm_postgresql_flexible_server.main.fqdn};Database=zdrive;Username=zdrive_admin;Password=${var.administrator_password}"
  sensitive   = true
}
