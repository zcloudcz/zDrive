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
