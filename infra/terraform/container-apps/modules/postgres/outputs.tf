output "fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "administrator_login" {
  value = azurerm_postgresql_flexible_server.main.administrator_login
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.zdrive.name
}
