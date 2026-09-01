# Azure Cache for Redis, Basic C0 — smallest SKU, no replication/SLA.
# Sufficient for a test environment.
resource "azurerm_redis_cache" "main" {
  name                = "redis-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  capacity = 0
  family   = "C"
  sku_name = "Basic"

  non_ssl_port_enabled = false
  minimum_tls_version  = "1.2"
}
