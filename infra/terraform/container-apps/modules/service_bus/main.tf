# Service Bus namespace only. No queues/topics are declared here: as of
# this writing no service in src/services actually publishes or consumes
# Service Bus messages yet (grepped for ServiceBusClient/queue/topic names —
# none found; the photo/notification event pipeline described in CLAUDE.md
# is not wired up in Phase 0-4). Add queues/topics here once a service
# needs them, named after what that service's code expects.
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
}
