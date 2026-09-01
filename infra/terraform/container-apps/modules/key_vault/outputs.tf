output "id" {
  value = azurerm_key_vault.main.id
}

output "uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "secret_ids" {
  description = "Map of secret name -> versionless Key Vault secret ID, for Container App secret refs."
  value       = { for name, secret in azurerm_key_vault_secret.this : name => secret.versionless_id }
}
