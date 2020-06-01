resource "azurerm_local_network_gateway" "onpremise" {
  name                = "lng-HEC45-test-01"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  gateway_address     = "168.62.225.23"
  address_space       = ["192.168.10.0/24"]
}

resource "azurerm_public_ip" "rg" {
  name                = "pip-VNG-HEC45-test-01"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "vng" {
  name                = "VNG-HEC45-test-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"

  ip_configuration {
    public_ip_address_id          = azurerm_public_ip.rg.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gatewaysubnet.id
  }
}

resource "azurerm_virtual_network_gateway_connection" "onpremise" {
  name                = "lng-HEC45-test-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vng.id
  local_network_gateway_id   = azurerm_local_network_gateway.onpremise.id

  shared_key = "xyz123"
}