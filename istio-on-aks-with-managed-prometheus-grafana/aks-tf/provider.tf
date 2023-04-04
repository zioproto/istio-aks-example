terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.10"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.4.0, < 2.0"
    }
  }
  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"

}

provider "azapi" {}