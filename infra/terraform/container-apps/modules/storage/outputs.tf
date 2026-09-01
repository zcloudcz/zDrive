output "connection_string" {
  value     = azurerm_storage_account.main.primary_connection_string
  sensitive = true
}

output "account_name" {
  value = azurerm_storage_account.main.name
}
