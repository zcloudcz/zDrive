variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

# Virtual Network for all zDrive resources
resource "azurerm_resource_group" "networking" {
  name     = "rg-${var.prefix}-${var.environment}-network"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.prefix}-${var.environment}"
  resource_group_name = azurerm_resource_group.networking.name
  location            = azurerm_resource_group.networking.location
  address_space       = ["10.0.0.0/16"]
}

# Subnet for AKS node pool
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/20"]
}

# Subnet for PostgreSQL Flexible Server (delegated)
resource "azurerm_subnet" "database" {
  name                 = "snet-database"
  resource_group_name  = azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.16.0/24"]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Subnet for private endpoints (Storage, Service Bus, etc.)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.17.0/24"]
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "database_subnet_id" {
  value = azurerm_subnet.database.id
}

output "private_endpoints_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}
