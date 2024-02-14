# Cloud journey with Atanu
Code is written by me to help organisation to adopt Infra as code model which helps dramatically to reduce the overall deployment timeline as well errorless deployment on production environment. 
Anyone in cloud and Network engineering space who is working to build their IAC foundation may use these materials to fulfil their journey.

Atanu´s Powershell scripts for Azure and AWS.

For the Team most interesting right now are probably: New-LoadBalancer.ps1 New-AppGw.ps1 New-VPN.ps1

Subsystem:

Connect-Azure Check if subscription can be called. Presents login-window if nessessary. Use: Connect-Azure("subscription-name")

Get-DataFromVnet Grabs the only vnet in the subscription and extracts resource-group, location and naming convention from it, returns the vnet. All parameters are optional. use: $vnet = Get-DataFromVnet -rg ([ref]$variable_for_rg-name) -location ([ref]$variable_for_rg-name) -hec_cid ([ref]$variable_for_hec-cid) -vnet $vnet_to_pull_info_from

Get-DeviceConfig Work in progress. Should display and download configuration file.

Get-StrongPSK generate a long PSK composed of lowercase, uppercase and numbers.

Set-String helper function that removes the need to "" when assigning strings to variables.

Azure:

Code Structure: $ErrorActionPreference = "stop" # Errors will stop the script rather than continue. $WarningPreference = "SilentlyContinue" Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true


