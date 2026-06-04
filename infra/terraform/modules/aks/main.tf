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
  description = "Subnet ID for AKS node pool"
  type        = string
}

resource "azurerm_resource_group" "aks" {
  name     = "rg-${var.prefix}-${var.environment}-aks"
  location = var.location
}

# AKS cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.prefix}-${var.environment}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  dns_prefix          = "${var.prefix}-${var.environment}"

  kubernetes_version = "1.29"

  default_node_pool {
    name           = "system"
    node_count     = var.environment == "production" ? 3 : 2
    vm_size        = var.environment == "production" ? "Standard_D4s_v5" : "Standard_B2ms"
    vnet_subnet_id = var.subnet_id

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
}

# Log Analytics for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.prefix}-${var.environment}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "production" ? 90 : 30
}

# Additional node pool for workloads (production only)
# resource "azurerm_kubernetes_cluster_node_pool" "workload" {
#   count                = var.environment == "production" ? 1 : 0
#   name                 = "workload"
#   kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
#   vm_size              = "Standard_D4s_v5"
#   node_count           = 3
#   vnet_subnet_id       = var.subnet_id
# }

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

output "host" {
  value = azurerm_kubernetes_cluster.main.kube_config[0].host
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}
