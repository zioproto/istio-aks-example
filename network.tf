
module "network-eastus" {
  source              = "Azure/network/azurerm"
  vnet_name           = azurerm_resource_group.eastus.name
  resource_group_name = azurerm_resource_group.eastus.name
  address_space       = "10.52.0.0/16"
  subnet_prefixes     = ["10.52.0.0/24", "10.52.1.0/24", "10.52.200.0/24"]
  subnet_names        = ["system", "user", "appgw"]
  depends_on          = [azurerm_resource_group.eastus]
  subnet_enforce_private_link_endpoint_network_policies = {
    "subnet1" : true
  }
}

module "network-westeurope" {
  source              = "Azure/network/azurerm"
  vnet_name           = azurerm_resource_group.westeurope.name
  resource_group_name = azurerm_resource_group.westeurope.name
  address_space       = "10.53.0.0/16"
  subnet_prefixes     = ["10.53.0.0/24", "10.53.1.0/24", "10.53.200.0/24"]
  subnet_names        = ["system", "user", "appgw"]
  depends_on          = [azurerm_resource_group.westeurope]
  subnet_enforce_private_link_endpoint_network_policies = {
    "subnet1" : true
  }
}

resource "azurerm_virtual_network_peering" "east2west" {
  name                      = "east2west"
  resource_group_name       = azurerm_resource_group.eastus.name
  virtual_network_name      = module.network-eastus.vnet_name
  remote_virtual_network_id = module.network-westeurope.vnet_id
}

resource "azurerm_virtual_network_peering" "west2east" {
  name                      = "west2east"
  resource_group_name       = azurerm_resource_group.westeurope.name
  virtual_network_name      = module.network-westeurope.vnet_name
  remote_virtual_network_id = module.network-eastus.vnet_id
}
