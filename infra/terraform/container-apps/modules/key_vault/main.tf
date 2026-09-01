data "azurerm_client_config" "current" {}

# RBAC authorization mode (not access policies) — matches how the
# container_apps module grants the apps' user-assigned identity read
# access via a role assignment.
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization = true
  purge_protection_enabled  = false # test env — allow clean teardown
}

# The identity running `terraform apply` needs write access to create the
# secrets below. In a real subscription this is normally granted once,
# out of band, to whoever/whatever runs Terraform (human or CI service
# principal) — this role assignment makes that dependency explicit.
resource "azurerm_role_assignment" "terraform_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "this" {
  # Secret names aren't secret material — only var.secrets' values are.
  # for_each can't iterate a sensitive map directly (the keys would be
  # tainted too), so this explicitly un-marks just the name list.
  for_each = nonsensitive(toset(keys(var.secrets)))

  name         = each.value
  value        = var.secrets[each.value]
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_secrets_officer]
}
