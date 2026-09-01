# Test environment on Azure Container Apps. Separate stack from
# ../modules/aks (and the ../main.tf root that wires it) — that AKS stack
# stays in the repo but is not called by this one. See
# docs/release-test-deploy.md "Rozhodnutí" for why: Container Apps was
# chosen over AKS for this environment (scale-to-zero, managed ingress).

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }

  # backend "azurerm" {
  #   resource_group_name  = "rg-zdrive-tfstate"
  #   storage_account_name = "stzdrivetfstate"
  #   container_name       = "tfstate"
  #   key                  = "zdrive-container-apps.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}-${var.environment}"
  location = var.location
}

module "postgres" {
  source = "./modules/postgres"

  environment         = var.environment
  location            = var.location
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  admin_password      = var.postgres_admin_password
}

module "redis" {
  source = "./modules/redis"

  environment         = var.environment
  location            = var.location
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
}

module "storage" {
  source = "./modules/storage"

  environment         = var.environment
  location            = var.location
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
}

module "service_bus" {
  source = "./modules/service_bus"

  environment         = var.environment
  location            = var.location
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
}

# Per-service connection strings — same server/database, different schema
# via "Search Path", matching each service's ConnectionStrings:{X}Db entry
# in its appsettings.json.
locals {
  db_host = module.postgres.fqdn
  db_base = "Host=${local.db_host};Port=5432;Database=${module.postgres.database_name};Username=${module.postgres.administrator_login};Password=${var.postgres_admin_password}"

  db_connection_strings = {
    auth         = "${local.db_base};Search Path=auth"
    file         = "${local.db_base};Search Path=files"
    storage      = "${local.db_base};Search Path=storage"
    sync         = "${local.db_base};Search Path=sync"
    photo        = "${local.db_base};Search Path=photos"
    notification = "${local.db_base};Search Path=notifications"
  }
}

module "key_vault" {
  source = "./modules/key_vault"

  environment         = var.environment
  location            = var.location
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name

  secrets = merge(
    {
      "jwt-private-key-pem"               = var.jwt_private_key_pem
      "jwt-public-key-pem"                = var.jwt_public_key_pem
      "auth-db-connection-string"         = local.db_connection_strings.auth
      "file-db-connection-string"         = local.db_connection_strings.file
      "storage-db-connection-string"      = local.db_connection_strings.storage
      "sync-db-connection-string"         = local.db_connection_strings.sync
      "photo-db-connection-string"        = local.db_connection_strings.photo
      "notification-db-connection-string" = local.db_connection_strings.notification
      "blob-storage-connection-string"    = module.storage.connection_string
    },
    # Redis and Service Bus are provisioned per the infra decision list, but
    # no service reads REDIS_CONNECTION_STRING or SERVICE_BUS_CONNECTION_STRING
    # today (grepped — no usage). Kept in the vault for when a service needs
    # them; not wired into any Container App env var yet (nothing to point at).
    {
      "redis-connection-string"       = module.redis.connection_string
      "service-bus-connection-string" = module.service_bus.connection_string
    }
  )
}

module "container_apps" {
  source = "./modules/container_apps"

  environment         = var.environment
  location            = var.location
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name

  key_vault_id = module.key_vault.id
  secret_ids = {
    jwt_private_key = module.key_vault.secret_ids["jwt-private-key-pem"]
    jwt_public_key  = module.key_vault.secret_ids["jwt-public-key-pem"]
    auth_db         = module.key_vault.secret_ids["auth-db-connection-string"]
    file_db         = module.key_vault.secret_ids["file-db-connection-string"]
    storage_db      = module.key_vault.secret_ids["storage-db-connection-string"]
    sync_db         = module.key_vault.secret_ids["sync-db-connection-string"]
    photo_db        = module.key_vault.secret_ids["photo-db-connection-string"]
    notification_db = module.key_vault.secret_ids["notification-db-connection-string"]
    blob_storage    = module.key_vault.secret_ids["blob-storage-connection-string"]
  }

  image_tag            = var.image_tag
  cors_allowed_origins = var.cors_allowed_origins
}
