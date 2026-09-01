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

variable "secrets" {
  description = "Map of secret name -> value to store in the vault (JWT keys, connection strings)."
  type        = map(string)
  sensitive   = true
}
