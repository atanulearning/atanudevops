## Includes ###########################################################################################
$ErrorActionPreference = "stop"     # Errors will stop the script rather than continue.
. .\subsystem\Connect-Azure.ps1     # Include login script
. .\subsystem\Get-DataFromVnet.ps1   # Include datagatherer  
. .\subsystem\Set-String.ps1         # Make manual data-input easy
. .\subsystem\Measure-ScriptTiming.ps1 # Save timing and show avarage.

## Part I: Data input #################################################################################

$sub=  "xyz-0457"          # Customer subscription
$sid=  Set-String WD1                   # System ID as per excel
$layer=Set-String nonprod                # prod/nonprod            
$backendIPs=@('10.215.33.15')          # @('192.168.174.15','192.168.174.16')

$backendPort="44380"                     # backend port
$backendProtocol="https"                 # backend protocol !This also determins probe protocol!
$frontPort="443"                         # lb listening port

## Optional input ######################################################################################

$healthProbeProtocol="tcp"              # can aso be set to $backendProtocol
$healthProbePath = "/ping/publicicp/show_init_statepub.icp"   # web-dispatcher default path is /sap/wdisp/admin/public/default.html  or /ping/publicicp/show_init_statepub.icp
$healthProbeInterval = '5'              # health probe every x seconds
$healthprobeCount = '2'                 # unhealthy after x failed attempts
$lbRuleProtocol = 'tcp'                 # tcp / udp
$sku = "Standard"                       # leave this on Standard
$subnetName = ""                        # Leave on "" to select default subnet for LBs

## Part II: sanity check ###############################################################################

$startTime = Get-Date
# WIP

if ($layer -eq "prod" -or $layer -eq "nonprod") { <#Sanity check OK#> }
else { return "Sanity check for layer failed. $layer" }

if($backendProtocol -eq "http" -or $backendProtocol -eq "https"){ <#Sanity check OK#> }
else { return "Sanity check for backendProtocol failed. $backendProtocol" }

if($healthProbeProtocol -eq "tcp" -or $healthProbeProtocol -eq "http" -or $healthProbeProtocol -eq "https"){ <#Sanity check OK#> }
else { return "Sanity check for healthProbeProtocol failed. $healthProbeProtocol" }

if($lbRuleProtocol -eq "tcp" -or $lbRuleProtocol -eq "udp"){ <#Sanity check OK#> }
else { return "Sanity check for lbRuleProtocol failed. $lbRuleProtocol" }

## Part III: logic #####################################################################################


$userInputTime=New-TimeSpan
Write-Host "Starting LB deployment. $startTime"
Connect-Azure($sub)
$location=$rg_name=$hec_cid=""
$vnet = Get-DataFromVnet -location ([ref]$location) -rg ([ref]$rg_Name) -hec_cid ([ref]$hec_cid)
$cid = ($hec_cid -split '-')[1]
$frontIpName =     "vh"+$cid.ToLower()+$sid.ToLower()+"lb"
$backendPoolName = "bp-"+$hec_cid+"-int-IB-"+$layer+"-"+$sid
$healthProbeName = "hp-"+$hec_cid+"-int-IB-"+$layer+"-"+$sid+"-"+$backendPort
$lbRuleName =  "lbrule-"+$hec_cid+"-int-IB-"+$layer+"-"+$sid+"-"+$backendPort
if ($subnetName -eq "") { $subnetName = "sn-"+$hec_cid+"-Public01-1" }

$subnetConfig= Get-AzVirtualNetworkSubnetConfig -name $subnetName -VirtualNetwork $vnet
$frontIp = New-AzLoadBalancerFrontendIpConfig -Name $frontIpName -Subnet $subnetConfig
$backendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name $backendPoolName
if ($healthProbeProtocol -eq "https" -or $healthProbeProtocol -eq "http") {
    $healthProbe = New-AzLoadBalancerProbeConfig -Name $healthProbeName -Protocol $healthProbeProtocol -Port $backendPort -RequestPath $healthProbePath -IntervalInSeconds $healthProbeInterval -ProbeCount $healthprobeCount
} else {
    $healthProbe = New-AzLoadBalancerProbeConfig -Name $healthProbeName -Protocol $healthProbeProtocol -Port $backendPort -IntervalInSeconds $healthProbeInterval -ProbeCount $healthprobeCount
}
$rule = New-AzLoadBalancerRuleConfig -Name $lbRuleName -Protocol $lbRuleProtocol -Probe $healthProbe -FrontendPort $frontPort -BackendPort $backendPort -FrontendIpConfiguration $frontIp -BackendAddressPool $backendPool -DisableOutboundSNAT 

Write-Host ""
$LBs = Get-AzLoadBalancer -ResourceGroupName $rg_name
if ( $LBs -is [System.Object]) {
    Write-Host "Existing LoadBalancer(s) found:"
    $counter=0
    $LBs | ForEach-Object {
        $counter++
        Write-Host $counter ":" $_.Name
    }
    $userInputTimeStart=Get-Date
    do {
        $LbNumber=Read-Host -Prompt "Please enter the number of the LB that you want to add this setup to. Enter 0 for new LB."
        # Exclude this from script runtime ?
    } while ($LbNumber -gt $counter -or $LbNumber -lt 0)
    $userInputTimeEnd=Get-Date
    $userInputTime=New-TimeSpan $userInputTimeStart $userInputTimeEnd 
    if ($LbNumber -eq 0) {
        switch ($counter) {
            { 1..8 -contains $_ } { 
                    $LbNumber= "-0" +($counter+1)
            }
            { 9 -eq $_ } {
                    $LbNumber= "-09"
            }
            Default {
                    $LbNumber= "-" +($counter+1)
            }
        }
        $loadBalancerName= "lb-"+$hec_cid+"-int-IB"+$LbNumber
        Write-Host ("Creating new LB: " + $loadBalancerName)
        $lb= New-AzLoadBalancer -Name $loadBalancerName -ResourceGroupName $rg_name -SKU $sku -Location $location -FrontendIpConfiguration $frontIp -BackendAddressPool $backendPool -Probe $healthProbe -LoadBalancingRule $rule
    }
    else {
        Write-Host "Existing LB selected."
        $counter=0
        $LBs | ForEach-Object {
            $counter++
            #Write-Host $lbNumber ":" $counter
            if ($counter -eq $lbNumber) {
                $lb=$_
                $loadBalancerName = $lb.Name
                $loadBalancerName | Out-Null         
            }
        }
        Write-Host "Adding setup to:" $loadBalancerName
        $lb.FrontendIpConfigurations.Add($frontIp)
        $lb.BackendAddressPools.Add($backendPool)
        $lb.Probes.Add($healthProbe)
        $lb.LoadBalancingRules.Add($rule)
        Set-AzLoadBalancer -LoadBalancer $lb | Out-Null
    }
}
else {
    $loadBalancerName= "lb-"+$hec_cid+"-int-IB-01"
    Write-Host ("Creating new LB: " + $loadBalancerName)
    $lb= New-AzLoadBalancer -Name $loadBalancerName -ResourceGroupName $rg_name -SKU $sku -Location $location -FrontendIpConfiguration $frontIp -BackendAddressPool $backendPool -Probe $healthProbe -LoadBalancingRule $rule
    #Remove-AzLoadBalancerFrontendIpConfig -Name "Public" -LoadBalancer $lb | Out-Null
    #Set-AzLoadBalancer -LoadBalancer $lb | Out-Null
}

Write-Host "Adding IPs to backend-pool."
$interfaces= Get-AzNetworkInterface
ForEach($thisInterface in $interfaces) {
    ForEach($thisIpConfig in $thisInterface.IpConfigurations){
        if ($backendIPs -contains $thisIpConfig.PrivateIpAddress) {
            Write-Host "Found IP:" $thisIpConfig.PrivateIpAddress " Adding to pool. (This may take a minute or five)."
            try {
                $thisIpConfig.LoadBalancerBackendAddressPools.Add($backendPool) 
                Set-AzNetworkInterface -NetworkInterface $thisInterface | Out-Null
                Write-Host ""
            }
            catch {
                Write-Host "Error while adding."
                ## if avialibility set error, role back
            }
            Write-Host "Backend was added."
        }
    } 
}
Write-Host "All backends added." 

$IpRegexV4='(?<Address>((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))'
do {
    Write-Host "Checking Front IP"
    $lb = Get-AzLoadBalancer -Name $loadBalancerName -ResourceGroupName $rg_name
    $newFrontIp = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $lb -Name $frontIpName
    $newFrontIp.PrivateIpAddress
    if ($newFrontIp.PrivateIpAddress -NotMatch $IpRegexV4) {
        Write-Host "Waiting for Ip to be assigned."
        Start-Sleep -Seconds 3
    }
} while ($newFrontIp.PrivateIpAddress -NotMatch $IpRegexV4)

# Calculate script timing
Measure-ScriptTiming -startTime ($startTime + $userInputTime)

Write-Host "Hello,"
Write-Host ""
Write-Host "We have configured: " $loadBalancerName
Write-Host "ip for SID" $sid ":" $newFrontIp.PrivateIpAddress
Write-Host ""
Write-Host "Thanks and Best Regards"
