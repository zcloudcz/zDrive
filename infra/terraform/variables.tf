variable "environment" {
  description = "Deployment environment (staging, production)"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "prefix" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "zdrive"
}

variable "postgres_administrator_password" {
  description = "PostgreSQL administrator password. Pass with -var or TF_VAR_postgres_administrator_password from a secret store; never commit it to a tfvars file."
  type        = string
  sensitive   = true
}
