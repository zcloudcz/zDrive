# Storage account backing StorageService. Azure Blob Versioning is
# intentionally NOT enabled: StorageService implements its own
# content-addressed chunk + manifest versioning (see CLAUDE.md "Blob
# versioning"), which is what the app actually relies on.
resource "azurerm_storage_account" "main" {
  name                     = "st${var.prefix}${var.environment}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
}

# Container names must match AzureBlobStorageService's SystemContainer /
# StorageContainer constants exactly. The service also self-creates them
# on demand (CreateIfNotExistsAsync), these just make provisioning explicit.
resource "azurerm_storage_container" "storage" {
  name                  = "zdrive-storage"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "system" {
  name                  = "zdrive-system"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}
