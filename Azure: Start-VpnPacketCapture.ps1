## PART I: Includes ###############################################################
$ErrorActionPreference = "stop" # Errors will stop the script rather than continue.
. .\subsystem\Connect-Azure.ps1     # Include login script
. .\subsystem\Get-DataFromVnet.ps1   # Gather data for naming        
. .\subsystem\Set-String.ps1         # Include script to make input below easy

## PART II: Data input ############################################################
$sub=Set-String subscription-number-0322
$vng_name=Set-String VNG-XYZ44-GWP-VPN
$con_name=Set-String VPN-XYZ44-GWP-01

## PART III: Logic ################################################################
Write-Output "Set Subscription"               
Connect-Azure($sub)
$location = $hecNumber_cid = $RG_Name = ""
Get-DataFromVnet -location ([ref]$location) -rg ([ref]$RG_Name) -hec_cid ([ref]$hecNumber_cid)

$storContext = New-AzStorageContext -StorageAccountName "vpndiagnosticsandlogs"
$sasurl = New-AzStorageContainerSASToken -Name "vpndiagnostics" -Permission "rwdl" -Context $storContext

$VNG = Get-AzVirtualNetworkGateway -ResourceGroupName $RG_Name -Name $vng_name
try {
    Write-Host "Start Capture"
    Start-AzVirtualnetworkGatewayPacketCapture -InputObject $VNG
    Write-Host "Capture packets for 300 seconds."
    Get-Date -Format "HH:mm:ss"
    Start-Sleep -s 300
}
finally {
    Write-Host "Stopping and saving results."
    Get-Date -Format "HH:mm:ss"
    Stop-AzVirtualNetworkGatewayPacketCapture -InputObject $VNG -SasUrl $sasurl
}



#Start-AzVirtualNetworkGatewayConnectionPacketCapture -ResourceGroupName $RG_Name -Name $con_name
#"Connection capture for 300 seconds."
#Start-Sleep -s 300
#Stop-AzVirtualNetworkGatewayConnectionPacketCapture -ResourceGroupName $RG_Name -Name $con_name -SasUrl $sasurl
