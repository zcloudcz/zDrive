output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "gateway_fqdn" {
  value = azurerm_container_app.gateway.latest_revision_fqdn
}

output "container_app_names" {
  description = "Map of service key -> Container App name, for `az containerapp update` in the deploy pipeline."
  value = merge(
    { for key, app in azurerm_container_app.worker : key => app.name },
    { gateway = azurerm_container_app.gateway.name }
  )
}
