variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "key_vault_id" {
  description = "Key Vault resource ID — used to grant the apps' identity read access to secrets."
  type        = string
}

variable "secret_ids" {
  description = "Versionless Key Vault secret IDs for JWT keys and per-service DB connection strings."
  type = object({
    jwt_private_key = string
    jwt_public_key  = string
    auth_db         = string
    file_db         = string
    storage_db      = string
    sync_db         = string
    photo_db        = string
    notification_db = string
    blob_storage    = string
  })
}

variable "placeholder_image" {
  description = <<-EOT
    Image used on first `terraform apply`, before any service image has been
    pushed to the ACR created by this module. Public so it pulls without
    registry credentials. Container Apps requires a valid, pullable image at
    creation time; the deploy pipeline (Agent 3) then flips each app to its
    real image via `az containerapp update`, which Terraform is told to
    ignore afterwards (see lifecycle.ignore_changes below).
  EOT
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "image_tag" {
  description = "Tag applied to `{acr_login_server}/{service}:{image_tag}` on the FIRST apply only (ignored on later applies, see placeholder_image)."
  type        = string
  default     = "latest"
}

variable "cors_allowed_origins" {
  description = "Origins the gateway allows via CORS (test client URL(s))."
  type        = list(string)
  default     = ["http://localhost:3000"]
}
