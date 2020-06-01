resource "azurerm_resource_group" "rg" {
    name                = "devresgrp"
    location            = "Southeast Asia"
}
resource "azurerm_virtual_network" "vnet" {
    name                 = "bluevirtualnetwork1"
    location             = azurerm_resource_group.rg.location
    resource_group_name  = azurerm_resource_group.rg.name
    address_space        = ["10.20.0.0/16"]
}
resource "azurerm_subnet" "gatewaysubnet" {
    name                 = "GatewaySubnet"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefix     = "10.20.2.0/24"
}