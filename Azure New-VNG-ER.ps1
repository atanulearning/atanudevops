# Create a new Azure Virtual network gateway for ExpressRoute, optional deploy shared connection.

## Includes ###########################################################################################

$ErrorActionPreference = "stop" # Errors will stop the script rather than continue.
. .\subsystem\Connect-Azure.ps1         # Include login script
. .\subsystem\Get-DataFromVnet.ps1       # Include data gatherer

## Part I: Data input #################################################################################

$sub = "xyz-0475"

## Optional input ######################################################################################

$RedeemAuthorization = $true
$authKey = "askakslas8-ghasj-41ce-aa74-asasjaskasec"
$peerId = "/subscriptions/abc/resourceGroups/rg-prod-shared-0001/providers/Microsoft.Network/expressRouteCircuits/erc-prod-0001"

## Part II: sanity check ###############################################################################

if ($authKey -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') {
    "Key Okay."
}
else {
    "Please provide the authorization Key in the format: "
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx where x is a hex symbol."
    exit
}
if ($peerId -match '/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/resourceGroups/.*/providers/Microsoft.Network/expressRouteCircuits/.*') {
    "Peer ID Okay."
}
else {
    "Peer ID is in invalid format."
    exit
}

## Part III: logic #####################################################################################

$timeStart=Get-Date
Connect-Azure($sub)
Write-Output "Get Virtual Network"      # Get data from azure
$location=$rgName=$hec_cid=""
$vnet = Get-DataFromVnet -location ([ref]$location) -rg ([ref]$rgName) -hec_cid ([ref]$hec_cid)
$gwName= "vng-" + $hec_cid + "-ER"
$GWIPName = "pip-" + $gwName
$GWIPconfName = "conf-" + $GWIPName

Write-Output "Get-AzVirtualNetworkSubnetConfig"
$subnet = Get-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet

Write-Output "Register New-AzPublicIpAddress"
$pip = New-AzPublicIpAddress -Name $GWIPName  -ResourceGroupName $rgName -Location $Location -AllocationMethod Dynamic

Write-Output "Create New-AzVirtualNetworkGatewayIpConfig"
$ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $subnet -PublicIpAddress $pip

Write-Output "Create New-AzVirtualNetworkGateway"
$vng_er = New-AzVirtualNetworkGateway -Name $gwName -ResourceGroupName $rgName -Location $location -IpConfigurations $ipconf -GatewayType Expressroute -GatewaySku Standard

if( $RedeemAuthorization -eq $true )
{
    $con_name = "er-" + $hec_cid + "-01"
    New-AzVirtualNetworkGatewayConnection -ConnectionType ExpressRoute -Name $con_name -ResourceGroupName $rgName -Location $location -VirtualNetworkGateway1 $vng_er -AuthorizationKey $authKey -PeerId $peerId

    Write-Output "Get-AzVirtualNetworkGateway Connection"
    $con = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $rgName -Name $con_name
}

Write-Output "Get-AzVirtualNetworkGateway"
$gw = Get-AzVirtualNetworkGateway -ResourceGroupName $rgName -Name $gwName

$con | Out-Null
$gw | Out-Null

Measure-ScriptTiming ($timeStart)
