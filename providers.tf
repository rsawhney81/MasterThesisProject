terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state backend (Azure Storage).
  # Provide values at init-time, for example:
  # terraform init \
  #   -backend-config="resource_group_name=rg-tfstate" \
  #   -backend-config="storage_account_name=<tfstate_storage>" \
  #   -backend-config="container_name=tfstate" \
  #   -backend-config="key=ecomm.${var.environment}.tfstate"
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
