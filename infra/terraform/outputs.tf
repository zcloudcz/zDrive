output "database_connection_string" {
  description = "PostgreSQL connection string"
  value       = module.database.connection_string
  sensitive   = true
}

output "storage_connection_string" {
  description = "Azure Blob Storage connection string"
  value       = module.storage.connection_string
  sensitive   = true
}

output "aks_kube_config" {
  description = "AKS cluster kubeconfig"
  value       = module.aks.kube_config
  sensitive   = true
}

output "aks_host" {
  description = "AKS cluster API server host"
  value       = module.aks.host
}
