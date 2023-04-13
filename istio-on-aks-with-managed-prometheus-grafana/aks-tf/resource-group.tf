resource "azurerm_resource_group" "this" {
  name     = "istio-aks"
  location = "eastus" # hardcoded because of the data collection endpoint name depending on the region
}