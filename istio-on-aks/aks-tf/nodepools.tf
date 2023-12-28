locals {
  node_pools = {
    user = {
      name                  = "user"
      kubernetes_cluster_id = module.aks.aks_id
      vm_size               = var.agents_size
      enable_auto_scaling   = true
      node_count            = 1
      min_count             = 1
      max_count             = 5
      vnet_subnet_id        = data.azurerm_subnet.system.id
    }
    ingress = {
      name                  = "ingress"
      kubernetes_cluster_id = module.aks.aks_id
      vm_size               = var.agents_size
      enable_auto_scaling   = true
      node_count            = 1
      min_count             = 1
      max_count             = 2
      vnet_subnet_id        = data.azurerm_subnet.system.id
      node_labels = {
        "nodepoolname" = "ingress"
      }
    }
  }
}
