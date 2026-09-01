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

variable "sku_name" {
  description = "Azure Cache for Redis SKU (Basic/Standard/Premium). All classic tiers are blocked for non-grandfathered tenants since 2026-04-01 — see infra/terraform/README.md."
  type        = string
  default     = "Basic"
}
