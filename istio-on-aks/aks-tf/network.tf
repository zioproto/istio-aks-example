module "network" {
  source              = "Azure/subnets/azurerm"
  version             = "1.0.0"
  resource_group_name = azurerm_resource_group.this.name
  subnets = {
    system = {
      address_prefixes = ["10.52.0.0/18"]
    }
    plc = {
      address_prefixes = ["10.52.192.0/24"]
    }
  }
  virtual_network_address_space = ["10.52.0.0/16"]
  virtual_network_location      = azurerm_resource_group.this.location
  virtual_network_name          = azurerm_resource_group.this.name
}