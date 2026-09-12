resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_registry" "main" {
  name                = "acr${var.prefix}${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false # apps pull via managed identity, see role_assignment.acr_pull
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.prefix}-${var.environment}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

# Single identity shared by every Container App: pulls images from the ACR
# and reads secrets from Key Vault. One identity keeps the role assignment
# count down (2, instead of 2 per app) — nothing here needs per-app isolation.
resource "azurerm_user_assigned_identity" "apps" {
  name                = "id-${var.prefix}-${var.environment}-apps"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
}

# depends_on only orders resource creation — it does not wait for Azure
# RBAC to actually propagate the role assignment. Without this gap, the
# first apply can have Container Apps try to read Key Vault secrets via
# the identity's brand-new role before it's authorized, and fail with a
# 403. 30s clears propagation in practice; bump if that's still flaky.
# triggers re-runs the sleep if the role assignment is ever replaced
# (e.g. the identity is recreated) — without it, the sleep only fires
# once, on the very first apply.
resource "time_sleep" "kv_role_propagation" {
  depends_on      = [azurerm_role_assignment.kv_secrets_user]
  create_duration = "30s"

  triggers = {
    role_assignment_id = azurerm_role_assignment.kv_secrets_user.id
  }
}

# The 6 non-gateway services. Shape is identical (public JWT key + own DB
# connection string); AuthService additionally needs the private key,
# StorageService additionally needs the blob connection string.
locals {
  worker_services = {
    auth = {
      db_secret_id      = var.secret_ids.auth_db
      db_env_name       = "AuthDb"
      needs_private_key = true
      needs_blob        = false
    }
    file = {
      db_secret_id      = var.secret_ids.file_db
      db_env_name       = "FileDb"
      needs_private_key = false
      needs_blob        = false
    }
    storage = {
      db_secret_id      = var.secret_ids.storage_db
      db_env_name       = "StorageDb"
      needs_private_key = false
      needs_blob        = true
    }
    sync = {
      db_secret_id      = var.secret_ids.sync_db
      db_env_name       = "SyncDb"
      needs_private_key = false
      needs_blob        = false
    }
    photo = {
      db_secret_id      = var.secret_ids.photo_db
      db_env_name       = "PhotoDb"
      needs_private_key = false
      needs_blob        = false
    }
    notification = {
      db_secret_id      = var.secret_ids.notification_db
      db_env_name       = "NotificationDb"
      needs_private_key = false
      needs_blob        = false
    }
  }
}

resource "azurerm_container_app" "worker" {
  for_each = local.worker_services

  name                         = "ca-${var.prefix}-${var.environment}-${each.key}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  dynamic "secret" {
    for_each = concat(
      [
        { name = "jwt-public-key", key_vault_secret_id = var.secret_ids.jwt_public_key },
        { name = "db-connection-string", key_vault_secret_id = each.value.db_secret_id },
      ],
      each.value.needs_private_key ? [{ name = "jwt-private-key", key_vault_secret_id = var.secret_ids.jwt_private_key }] : [],
      each.value.needs_blob ? [{ name = "blob-connection-string", key_vault_secret_id = var.secret_ids.blob_storage }] : []
    )
    content {
      name                = secret.value.name
      identity            = azurerm_user_assigned_identity.apps.id
      key_vault_secret_id = secret.value.key_vault_secret_id
    }
  }

  template {
    min_replicas = 0 # scale-to-zero — no traffic guarantee needed for a test env
    max_replicas = 3

    container {
      name   = each.key
      image  = var.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = "Production"
      }

      dynamic "env" {
        for_each = concat(
          [
            { name = "Jwt__RsaPublicKeyPem", secret_name = "jwt-public-key" },
            { name = "ConnectionStrings__${each.value.db_env_name}", secret_name = "db-connection-string" },
          ],
          each.value.needs_private_key ? [{ name = "Jwt__RsaPrivateKeyPem", secret_name = "jwt-private-key" }] : [],
          each.value.needs_blob ? [{ name = "ConnectionStrings__AzureBlobStorage", secret_name = "blob-connection-string" }] : []
        )
        content {
          name        = env.value.name
          secret_name = env.value.secret_name
        }
      }

      # Gated by enable_health_probes — see that variable's description for
      # why (placeholder_image doesn't serve these paths at bootstrap).
      dynamic "liveness_probe" {
        for_each = var.enable_health_probes ? [1] : []
        content {
          transport = "HTTP"
          path      = "/health/live"
          port      = 8080
        }
      }

      dynamic "readiness_probe" {
        for_each = var.enable_health_probes ? [1] : []
        content {
          transport = "HTTP"
          path      = "/health/ready"
          port      = 8080
        }
      }
    }
  }

  ingress {
    external_enabled = false # internal-only — reached via the gateway or other services
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # The deploy pipeline (Agent 3) updates the image via `az containerapp
  # update` on every deploy. Terraform must not fight that on the next
  # plan/apply — it only owns the placeholder used for initial bootstrap.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    time_sleep.kv_role_propagation,
  ]
}

# Gateway: external ingress (public FQDN + managed TLS), min 1 replica, and
# the YARP cluster addresses pointed at the other apps' internal FQDNs.
# Cluster/destination IDs must match ApiGateway/appsettings.json's
# ReverseProxy section verbatim: they are spliced into the env var name below,
# and a mismatch does not fail — YARP adds a *second* destination and sends
# half the traffic to the unreachable localhost default from appsettings.
#
# The IDs deliberately carry no hyphens. Azure App Service on Linux exposes app
# settings as environment variables and rejects any name containing "-" with a
# bare "Bad Request", which made the original auth-cluster/auth-service ids
# impossible to configure there.
locals {
  gateway_clusters = {
    auth    = { cluster_id = "authCluster", destination_id = "authService" }
    file    = { cluster_id = "fileCluster", destination_id = "fileService" }
    storage = { cluster_id = "storageCluster", destination_id = "storageService" }
    sync    = { cluster_id = "syncCluster", destination_id = "syncService" }
    photo   = { cluster_id = "photoCluster", destination_id = "photoService" }
    # Carries both /api/v1/notifications and the SignalR hub at /hubs/sync/**.
    notification = { cluster_id = "notificationCluster", destination_id = "notificationService" }
  }
}

resource "azurerm_container_app" "gateway" {
  name                         = "ca-${var.prefix}-${var.environment}-gateway"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  secret {
    name                = "jwt-public-key"
    identity            = azurerm_user_assigned_identity.apps.id
    key_vault_secret_id = var.secret_ids.jwt_public_key
  }

  template {
    min_replicas = 1 # gateway is the public entry point — never scale to zero
    max_replicas = 3

    container {
      name   = "gateway"
      image  = var.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = "Production"
      }

      env {
        name        = "Jwt__RsaPublicKeyPem"
        secret_name = "jwt-public-key"
      }

      dynamic "env" {
        for_each = local.gateway_clusters
        content {
          name = "ReverseProxy__Clusters__${env.value.cluster_id}__Destinations__${env.value.destination_id}__Address"
          # ingress[0].fqdn is the app's stable FQDN — unlike
          # latest_revision_fqdn it does not change on every `az
          # containerapp update` the deploy pipeline runs, so the gateway
          # never routes to a since-replaced revision. https:// because
          # Container Apps ingress (internal or external) only accepts TLS
          # unless allow_insecure_connections is set — plain http:// gets
          # redirected, which YARP would forward as-is instead of proxying.
          value = "https://${azurerm_container_app.worker[env.key].ingress[0].fqdn}"
        }
      }

      dynamic "env" {
        for_each = { for idx, origin in var.cors_allowed_origins : tostring(idx) => origin }
        content {
          name  = "Cors__AllowedOrigins__${env.key}"
          value = env.value
        }
      }

      # Gated by enable_health_probes — see that variable's description for
      # why (placeholder_image doesn't serve these paths at bootstrap).
      dynamic "liveness_probe" {
        for_each = var.enable_health_probes ? [1] : []
        content {
          transport = "HTTP"
          path      = "/health/live"
          port      = 8080
        }
      }

      dynamic "readiness_probe" {
        for_each = var.enable_health_probes ? [1] : []
        content {
          transport = "HTTP"
          path      = "/health/ready"
          port      = 8080
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    time_sleep.kv_role_propagation,
  ]
}
