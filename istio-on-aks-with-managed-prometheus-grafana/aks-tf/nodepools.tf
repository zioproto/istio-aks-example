locals {
  node_pools = {
    user = {
      name                = "user"
      vm_size             = var.agents_size
      enable_auto_scaling = true
      node_count          = 1
      min_count           = 1
      max_count           = 5
      vnet_subnet_id      = module.network.vnet_subnets[0]
    },
    ingress = {
      name                = "ingress"
      vm_size             = var.agents_size
      enable_auto_scaling = true
      node_count          = 1
      min_count           = 1
      max_count           = 2
      vnet_subnet_id      = module.network.vnet_subnets[0]
    },
  }
}