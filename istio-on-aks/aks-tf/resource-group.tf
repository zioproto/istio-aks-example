resource "azurerm_resource_group" "this" {
  name     = "istio-aks"
  location = var.region
}