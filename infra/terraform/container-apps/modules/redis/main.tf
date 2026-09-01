# Azure Cache for Redis C0 — smallest SKU, no replication/SLA. Sufficient
# for a test environment. sku_name is a variable (not hardcoded "Basic")
# because Microsoft blocks new classic-tier Azure Cache for Redis creation
# for non-grandfathered tenants as of 2026-04-01 — see README "Known gaps"
# for what that means for `apply` in your subscription.
resource "azurerm_redis_cache" "main" {
  name                = "redis-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  capacity = 0
  family   = "C"
  sku_name = var.sku_name

  # Arg name pinned to azurerm ~> 3.90 — non_ssl_port_enabled only exists
  # from azurerm 4.x onward.
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
}
