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

    Must listen on port 8080 (target_port, hardcoded below) — when
    enable_health_probes is false, Container Apps still runs its own
    default TCP startup/liveness probe against target_port (omitting an
    explicit probe block does not disable probing), so a placeholder that
    doesn't listen there fails to come up. mcr.microsoft.com/dotnet/samples
    is the official .NET sample app; .NET 8+ container images default to
    port 8080.
  EOT
  type        = string
  default     = "mcr.microsoft.com/dotnet/samples:aspnetapp"
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

variable "enable_health_probes" {
  description = <<-EOT
    Whether Container Apps run explicit HTTP liveness/readiness probes
    against /health/live and /health/ready on port 8080. Default false
    because placeholder_image doesn't serve those paths — the bootstrap
    apply relies on Container Apps' default TCP probe against
    target_port instead (which the placeholder does satisfy, see
    placeholder_image). Set true and re-apply once the deploy pipeline
    has flipped every app to its real service image.
  EOT
  type        = bool
  default     = false
}
