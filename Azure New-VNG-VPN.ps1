$ErrorActionPreference = "stop" # Errors will stop the script rather than continue.
. .\subsystem\Connect-Azure.ps1         # Include login script
. .\subsystem\Get-DataFromVnet.ps1       # Include data gatherer

Select-AzSubscription -SubscriptionName "xyz-0215"
$vng_vpn_type= "RouteBased"             # "RouteBased" | "PolicyBased"
$vng_type = "vpn"
$vng_sku= "VpnGw1"    # Basic, Standard, HighPerformance, UltraPerformance, VpnGw1, VpnGw2, VpnGw3, VpnGw1AZ, VpnGw2AZ, VpnGw3AZ, ErGw1AZ, ErGw2AZ, ErGw3AZ

Write-Output "Get Virtual Network"      # Get data from azure
$location=""
$rg_name=""
$hec_cid=""
$vnet=Get-AzVirtualNetwork                 # get details about the vnet of currently connected subscription to extract:
Get-DataFromVnet -location ([ref]$location) -rg ([ref]$rg_Name) -hec_cid ([ref]$hec_cid) -vnet $vnet
$GWName= "vng-" + $hec_cid + "-VPN"
$GWIPName = "pip-" + $GWName
$GWIPconfName = "conf-" + $GWIPName

Write-Output "Get-AzVirtualNetworkSubnetConfig"
$subnet = Get-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet

Write-Output "New-AzPublicIpAddress"
$pip = New-AzPublicIpAddress -Name $GWIPName  -ResourceGroupName $rg_Name -Location $Location -AllocationMethod Dynamic

Write-Output "New-AzVirtualNetworkGatewayIpConfig"
$ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $subnet -PublicIpAddress $pip

Write-Output "New-AzVirtualNetworkGateway"
New-AzVirtualNetworkGateway -Name $GWName -ResourceGroupName $rg_Name -Location $Location -IpConfigurations $ipconf -GatewayType $vng_type -VpnType $vng_vpn_type -GatewaySku $vng_sku
#ToDo active-active
Write-Output "Get-AzVirtualNetworkGateway"
Get-AzVirtualNetworkGateway -ResourceGroupName $rg_Name
