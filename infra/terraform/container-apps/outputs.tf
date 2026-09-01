output "gateway_fqdn" {
  description = "Public FQDN of the gateway Container App — the test environment's entry point."
  value       = module.container_apps.gateway_fqdn
}

output "acr_login_server" {
  description = "ACR login server the deploy pipeline pushes images to (docker/az acr build target)."
  value       = module.container_apps.acr_login_server
}

output "container_app_names" {
  description = "Map of service key (gateway, auth, file, storage, sync, photo, notification) -> Container App name, for `az containerapp update`."
  value       = module.container_apps.container_app_names
}

output "key_vault_uri" {
  description = "Key Vault URI holding JWT keys and connection strings."
  value       = module.key_vault.uri
}

output "resource_group_name" {
  description = "Resource group the deploy pipeline targets with `az containerapp` / `az acr` commands."
  value       = azurerm_resource_group.main.name
}
