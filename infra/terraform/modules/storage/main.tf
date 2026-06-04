variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

resource "azurerm_resource_group" "storage" {
  name     = "rg-${var.prefix}-${var.environment}-storage"
  location = var.location
}

# Storage account for blob storage (file content, photos, thumbnails)
resource "azurerm_storage_account" "main" {
  name                     = "st${var.prefix}${var.environment}"
  resource_group_name      = azurerm_resource_group.storage.name
  location                 = azurerm_resource_group.storage.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "production" ? "GRS" : "LRS"
  account_kind             = "StorageV2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

# Container for user file blobs
resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Container for photo thumbnails (CDN-served)
resource "azurerm_storage_container" "thumbnails" {
  name                  = "thumbnails"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Container for temporary upload chunks
resource "azurerm_storage_container" "chunks" {
  name                  = "chunks"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

output "connection_string" {
  description = "Storage account connection string"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}
