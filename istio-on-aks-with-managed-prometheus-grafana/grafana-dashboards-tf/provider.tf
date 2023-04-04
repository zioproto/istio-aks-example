terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.10"
    }
    grafana = {
      source = "grafana/grafana"
      version = "1.36.1"
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

# https://learn.microsoft.com/en-gb/azure/managed-grafana/how-to-api-calls
provider "grafana" {
  # az grafana show -g istio-aks -n istio-grafana -o json | jq .properties.endpoint
  url = "https://istio-grafana-g9ckhsdxf6ayccc3.eus.grafana.azure.com"

  # To obtain the token, you can use the following command:
  # az grafana api-key create --key keyname --name istio-grafana -g istio-aks -r editor -o json
  auth = ""
}
