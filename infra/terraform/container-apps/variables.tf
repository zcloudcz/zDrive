variable "environment" {
  description = "Deployment environment name, used in resource naming."
  type        = string
  default     = "test"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "prefix" {
  description = "Naming prefix for all resources."
  type        = string
  default     = "zdrive"
}

variable "postgres_admin_password" {
  description = "PostgreSQL Flexible Server admin password. Supply via -var / TF_VAR_ / a gitignored *.auto.tfvars — never commit it."
  type        = string
  sensitive   = true
}

variable "jwt_private_key_pem" {
  description = "RSA private key (PEM) AuthService signs JWTs with. Generate with `openssl genrsa`, never commit it."
  type        = string
  sensitive   = true
}

variable "jwt_public_key_pem" {
  description = "RSA public key (PEM) matching jwt_private_key_pem, used by every service to validate JWTs."
  type        = string
  sensitive   = true
}

variable "image_tag" {
  description = "Image tag used on the FIRST apply only (before any real image exists in the ACR). See container_apps module's placeholder_image for why later applies ignore this."
  type        = string
  default     = "latest"
}

variable "cors_allowed_origins" {
  description = "Origins the gateway allows via CORS (the test Flutter client's URL(s))."
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "redis_sku_name" {
  description = "Azure Cache for Redis SKU (Basic/Standard/Premium). All classic tiers are blocked for non-grandfathered tenants since 2026-04-01 — see infra/terraform/README.md."
  type        = string
  default     = "Basic"
}

variable "enable_health_probes" {
  description = "Enable liveness/readiness probes on the Container Apps. Keep false for the bootstrap apply (placeholder image doesn't serve /health/*); set true and re-apply once real service images are deployed. See infra/terraform/README.md."
  type        = bool
  default     = false
}
