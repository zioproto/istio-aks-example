locals {
  node_pools_west = {
    user = {
      name                = "user"
      vm_size             = var.agents_size
      enable_auto_scaling = true
      node_count          = 1
      min_count           = 1
      max_count           = 5
      vnet_subnet_id      = module.network-westeurope.vnet_subnets[1]
    }
  }
  node_pools_east = {
    user = {
      name                = "user"
      vm_size             = var.agents_size
      enable_auto_scaling = true
      node_count          = 1
      min_count           = 1
      max_count           = 5
      vnet_subnet_id      = module.network-eastus.vnet_subnets[1]
    }
  }
}

