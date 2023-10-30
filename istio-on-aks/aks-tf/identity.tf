resource "azurerm_user_assigned_identity" "alb_controller" {
  name                = "azure-alb-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

data "azurerm_resource_group" "node_rg" {
  name       = module.aks.node_resource_group
  depends_on = [module.aks]
}

# https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller?tabs=install-helm-windows
resource "azurerm_role_assignment" "alb_controller" {
  scope = data.azurerm_resource_group.node_rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
}

resource "azurerm_federated_identity_credential" "alb_controller" {
  name                = "azure-alb-identity"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.alb_controller.id
  subject             = "system:serviceaccount:azure-alb-system:alb-controller-sa"
  depends_on          = [module.aks]
}

# Delegate AppGw for Containers Configuration Manager role to AKS Managed Cluster RG
#az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --scope $mcResourceGroupId --role "fbc52c3f-28ad-4303-a892-8a056630b8f1"

resource "azurerm_role_assignment" "containers_configuration_manager" {
  scope = data.azurerm_resource_group.node_rg.id
  role_definition_name = "AppGw for Containers Configuration Manager"
  principal_id       = azurerm_user_assigned_identity.alb_controller.principal_id
  depends_on         = [module.aks]
}

# Delegate Network Contributor permission for join to association subnet
# az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --scope $ALB_SUBNET_ID --role "4d97b98b-1d4f-4787-a291-c67834d212e7"

resource "azurerm_role_assignment" "network_contributor" {
  scope                = data.azurerm_subnet.subnet-alb.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
  depends_on           = [module.network]
}
