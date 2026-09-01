output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "gateway_fqdn" {
  # Stable FQDN, not latest_revision_fqdn — the latter changes on every
  # `az containerapp update` and would break the deploy pipeline's smoke
  # test / any client pointed at this output after the first real deploy.
  value = azurerm_container_app.gateway.ingress[0].fqdn
}

output "container_app_names" {
  description = "Map of service key -> Container App name, for `az containerapp update` in the deploy pipeline."
  value = merge(
    { for key, app in azurerm_container_app.worker : key => app.name },
    { gateway = azurerm_container_app.gateway.name }
  )
}
