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

variable "admin_password" {
  description = "PostgreSQL admin password. Never set a default — must come from a var not committed to git."
  type        = string
  sensitive   = true
}
