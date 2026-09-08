terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # backend "azurerm" {
  #   resource_group_name  = "rg-zdrive-tfstate"
  #   storage_account_name = "stzdrivetfstate"
  #   container_name       = "tfstate"
  #   key                  = "zdrive.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

module "networking" {
  source = "./modules/networking"

  environment = var.environment
  location    = var.location
  prefix      = var.prefix
}

module "database" {
  source = "./modules/database"

  environment            = var.environment
  location               = var.location
  prefix                 = var.prefix
  subnet_id              = module.networking.database_subnet_id
  administrator_password = var.postgres_administrator_password
}

module "storage" {
  source = "./modules/storage"

  environment = var.environment
  location    = var.location
  prefix      = var.prefix
}

module "aks" {
  source = "./modules/aks"

  environment = var.environment
  location    = var.location
  prefix      = var.prefix
  subnet_id   = module.networking.aks_subnet_id
}
