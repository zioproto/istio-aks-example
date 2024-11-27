module "aks" {
  source                            = "Azure/aks/azurerm"
  version                           = "9.2.0"
  resource_group_name               = azurerm_resource_group.this.name
  kubernetes_version                = var.kubernetes_version
  orchestrator_version              = var.kubernetes_version
  prefix                            = "istio"
  network_plugin                    = "azure"
  vnet_subnet_id                    = data.azurerm_subnet.system.id
  os_disk_size_gb                   = 50
  sku_tier                          = "Standard"
  role_based_access_control_enabled = true
  rbac_aad                          = false
  private_cluster_enabled           = false
  enable_auto_scaling               = true
  enable_host_encryption            = false
  log_analytics_workspace_enabled   = true
  agents_min_count                  = 1
  agents_max_count                  = 5
  agents_count                      = null # Please set `agents_count` `null` while `enable_auto_scaling` is `true` to avoid possible `agents_count` changes.
  agents_max_pods                   = 100
  agents_pool_name                  = "system"
  agents_availability_zones         = ["1", "2"]
  agents_type                       = "VirtualMachineScaleSets"
  agents_size                       = var.agents_size
  green_field_application_gateway_for_ingress = {
    name = "ingress"
    subnet_cidr = "10.52.32.0/20"
  }

  network_contributor_role_assigned_subnet_ids = {
  system = data.azurerm_subnet.system.id
  alb    = data.azurerm_subnet.subnet-alb.id

  }

  agents_labels = {
    "nodepool" : "defaultnodepool"
  }

  agents_tags = {
    "Agent" : "defaultnodepoolagent"
  }

  network_policy             = "azure"
  net_profile_dns_service_ip = "10.0.0.10"
  net_profile_service_cidr   = "10.0.0.0/16"

  key_vault_secrets_provider_enabled = true
  secret_rotation_enabled            = true
  secret_rotation_interval           = "3m"

  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  node_pools = local.node_pools

  log_analytics_workspace = {
    id = azurerm_log_analytics_workspace.this.id
    name = azurerm_log_analytics_workspace.this.name
    location = azurerm_resource_group.this.location
    resource_group_name = azurerm_resource_group.this.name
  }

  depends_on = [module.network]
}

resource "azurerm_log_analytics_workspace" "this" {
  location            = azurerm_resource_group.this.location
  name                = "log-istio-aks"
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                           = "amds-istio-aks"
  target_resource_id             = module.aks.aks_id
  log_analytics_destination_type = "Dedicated"
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id

  # Kubernetes API Server
  enabled_log {
    category = "kube-apiserver"
  }
  # Kubernetes Audit
  enabled_log {
    category = "kube-audit"
  }
  # Kubernetes Audit Admin Logs
  enabled_log {
    category = "kube-audit-admin"
  }
  # Kubernetes Controller Manager
  enabled_log {
    category = "kube-controller-manager"
  }
  # Kubernetes Scheduler
  enabled_log {
    category = "kube-scheduler"
  }
  #Kubernetes Cluster Autoscaler
  enabled_log {
    category = "cluster-autoscaler"
  }
  #Kubernetes Cloud Controller Manager
  enabled_log {
    category = "cloud-controller-manager"
  }
  #guard
  enabled_log {
    category = "guard"
  }
  #csi-azuredisk-controller
  enabled_log {
    category = "csi-azuredisk-controller"
  }
  #csi-azurefile-controller
  enabled_log {
    category = "csi-azurefile-controller"
  }
  #csi-snapshot-controller
  enabled_log {
    category = "csi-snapshot-controller"
  }
  metric {
    category = "AllMetrics"
  }
}