output "connection_string" {
  value     = azurerm_redis_cache.main.primary_connection_string
  sensitive = true
}
