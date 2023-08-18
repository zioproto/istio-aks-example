module "network" {
  source              = "Azure/network/azurerm"
  vnet_name           = azurerm_resource_group.this.name
  resource_group_name = azurerm_resource_group.this.name
  address_space       = "10.52.0.0/16"
  subnet_prefixes     = ["10.52.0.0/20", "10.52.16.0/20"]
  subnet_names        = ["system", "subnet-alb"]
  depends_on          = [azurerm_resource_group.this]
  use_for_each        = true
  subnet_delegation = {
    subnet-alb = [
      {
      name    = "delegation"
      service_delegation = {
        name = "Microsoft.ServiceNetworking/trafficControllers"
      }
      }
    ]
  }
}

# Create a DataSource to be able to reference subnet by name elsewhere
data "azurerm_subnet" "system" {
  name                 = "system"
  virtual_network_name = module.network.vnet_name
  resource_group_name  = azurerm_resource_group.this.name
  depends_on           = [module.network]
}

data "azurerm_subnet" "subnet-alb" {
  name                 = "subnet-alb"
  virtual_network_name = module.network.vnet_name
  resource_group_name  = azurerm_resource_group.this.name
  depends_on           = [module.network]
}
