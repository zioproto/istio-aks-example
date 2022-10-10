resource "azurerm_kubernetes_cluster_node_pool" "westuserpool" {
  name                  = "user"
  kubernetes_cluster_id = module.aks-westeurope.aks_id
  vm_size               = var.agents_size
  enable_auto_scaling   = true
  node_count            = 1
  min_count             = 1
  max_count             = 5
  vnet_subnet_id        = module.network-westeurope.vnet_subnets[1]
  depends_on            = [module.network-westeurope]
}

resource "azurerm_kubernetes_cluster_node_pool" "eastuserpool" {
  name                  = "user"
  kubernetes_cluster_id = module.aks-eastus.aks_id
  vm_size               = var.agents_size
  enable_auto_scaling   = true
  node_count            = 1
  min_count             = 1
  max_count             = 5
  vnet_subnet_id        = module.network-eastus.vnet_subnets[1]
  depends_on            = [module.network-eastus]
}

