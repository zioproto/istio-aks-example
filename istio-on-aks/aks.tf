module "aks" {
  source                           = "Azure/aks/azurerm"
  version                          = "6.7.1"
  resource_group_name              = azurerm_resource_group.this.name
  kubernetes_version               = var.kubernetes_version
  orchestrator_version             = var.kubernetes_version
  prefix                           = "istio"
  network_plugin                   = "azure"
  vnet_subnet_id                   = lookup(module.network.vnet_subnets_name_id, "system")
  os_disk_size_gb                  = 50
  sku_tier                         = "Paid" # defaults to Free
  private_cluster_enabled          = false
  http_application_routing_enabled = false
  enable_auto_scaling              = true
  enable_host_encryption           = false
  log_analytics_workspace_enabled  = false
  agents_min_count                 = 1
  agents_max_count                 = 5
  agents_count                     = null # Please set `agents_count` `null` while `enable_auto_scaling` is `true` to avoid possible `agents_count` changes.
  agents_max_pods                  = 100
  agents_pool_name                 = "system"
  agents_availability_zones        = ["1", "2"]
  agents_type                      = "VirtualMachineScaleSets"
  agents_size                      = var.agents_size

  agents_labels = {
    "nodepool" : "defaultnodepool"
  }

  agents_tags = {
    "Agent" : "defaultnodepoolagent"
  }

  ingress_application_gateway_enabled = false

  network_policy                 = "azure"
  net_profile_dns_service_ip     = "10.0.0.10"
  net_profile_docker_bridge_cidr = "172.17.0.1/16"
  net_profile_service_cidr       = "10.0.0.0/16"

  key_vault_secrets_provider_enabled = true
  secret_rotation_enabled            = true
  secret_rotation_interval           = "3m"

  role_based_access_control_enabled = true
  rbac_aad                          = false

  depends_on = [module.network]
}

# Grant AKS cluster access to use AKS subnet
# https://github.com/Azure/terraform-azurerm-aks/issues/178
resource "azurerm_role_assignment" "aks" {
  principal_id         = module.aks.cluster_identity.principal_id
  role_definition_name = "Network Contributor"
  scope                = lookup(module.network.vnet_subnets_name_id, "system")
  depends_on           = [module.aks]
}

resource "azurerm_role_assignment" "plc" {
  principal_id         = module.aks.cluster_identity.principal_id
  role_definition_name = "Network Contributor"
  scope                = lookup(module.network.vnet_subnets_name_id, "plc")
  depends_on           = [module.aks]
}