resource "random_string" "random" {
  length  = 6
  special = false
  upper   = false
}

module "aks-westeurope" {
  source                            = "github.com/Azure/terraform-azurerm-aks.git?ref=2fdde3c4d1079ce7f8119f3caccc59d9d7d117a1"
  #source                            = "Azure/aks/azurerm"
  #version                           = "8.0.0"
  resource_group_name               = azurerm_resource_group.westeurope.name
  kubernetes_version                = var.kubernetes_version
  orchestrator_version              = var.kubernetes_version
  prefix                            = azurerm_resource_group.westeurope.location
  network_plugin                    = "azure"
  vnet_subnet_id                    = module.network-westeurope.vnet_subnets[0]
  os_disk_size_gb                   = 50
  sku_tier                          = "Standard"
  role_based_access_control_enabled = true
  rbac_aad                          = false
  private_cluster_enabled           = false
  azure_policy_enabled              = true
  enable_auto_scaling               = true
  enable_host_encryption            = false
  log_analytics_workspace_enabled   = false
  agents_min_count                  = 1
  agents_max_count                  = 5
  agents_count                      = null # Please set `agents_count` `null` while `enable_auto_scaling` is `true` to avoid possible `agents_count` changes.
  agents_max_pods                   = 100
  agents_pool_name                  = "system"
  agents_availability_zones         = ["1", "2"]
  agents_type                       = "VirtualMachineScaleSets"
  agents_size                       = var.agents_size

  agents_labels = {
    "nodepool" : "defaultnodepool"
  }

  agents_tags = {
    "Agent" : "defaultnodepoolagent"
  }

  green_field_application_gateway_for_ingress = {
    name      = "aks-agw-westeurope"
    subnet_id = module.network-westeurope.vnet_subnets[2]
  }

  network_policy             = "azure"
  net_profile_dns_service_ip = "10.0.0.10"
  net_profile_service_cidr   = "10.0.0.0/16"

  key_vault_secrets_provider_enabled = true
  secret_rotation_enabled            = true
  secret_rotation_interval           = "3m"

  node_pools = local.node_pools_west

  depends_on = [module.network-westeurope]
}

module "aks-eastus" {
  source                            = "Azure/aks/azurerm"
  version                           = "7.5.0"
  resource_group_name               = azurerm_resource_group.eastus.name
  kubernetes_version                = var.kubernetes_version
  orchestrator_version              = var.kubernetes_version
  prefix                            = azurerm_resource_group.eastus.location
  network_plugin                    = "azure"
  vnet_subnet_id                    = module.network-eastus.vnet_subnets[0]
  os_disk_size_gb                   = 50
  sku_tier                          = "Standard"
  role_based_access_control_enabled = true
  rbac_aad                          = false
  private_cluster_enabled           = false
  http_application_routing_enabled  = false
  azure_policy_enabled              = true
  enable_auto_scaling               = true
  enable_host_encryption            = false
  log_analytics_workspace_enabled   = false
  agents_min_count                  = 1
  agents_max_count                  = 5
  agents_count                      = null # Please set `agents_count` `null` while `enable_auto_scaling` is `true` to avoid possible `agents_count` changes.
  agents_max_pods                   = 100
  agents_pool_name                  = "system"
  agents_availability_zones         = ["1", "2"]
  agents_type                       = "VirtualMachineScaleSets"
  agents_size                       = var.agents_size

  agents_labels = {
    "nodepool" : "defaultnodepool"
  }

  agents_tags = {
    "Agent" : "defaultnodepoolagent"
  }

  ingress_application_gateway_enabled = false

  network_policy             = "azure"
  net_profile_dns_service_ip = "10.1.0.10"
  net_profile_service_cidr   = "10.1.0.0/16"

  key_vault_secrets_provider_enabled = true
  secret_rotation_enabled            = true
  secret_rotation_interval           = "3m"

  node_pools = local.node_pools_east

  depends_on = [module.network-eastus]
}
