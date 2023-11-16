## PART I: Includes ###############################################################

. .\subsystem\Send-AlertEmail.ps1
. .\subsystem\Connect-Azure.ps1         # Include login script
. .\subsystem\Get-AzureAccounts.ps1
. .\subsystem\Get-ProjectLeadEmail.ps1
. .\subsystem\Measure-ScriptTiming.ps1


$oldverbose = $VerbosePreference
#$VerbosePreference = "continue"        # Uncomment for verbose output.
$WarningPreference = "SilentlyContinue"

## PART II: Data input ############################################################

$ExpiresInDays = 60

## PART III: Logic ################################################################

$startTime = get-Date
$userInputTime=New-TimeSpan
Write-verbose "Verbose mode enabled."

if ((Get-Module -Name Az.* -ListAvailable)) {
    Write-Host "Az module is installed, continue." }
else {
    Write-Host "Az module not found, installing."
    Install-Module -Name Az -AllowClobber -Scope CurrentUser 
}
if ((Get-Module -Name Az.ResourceGraph -ListAvailable)) {
    Write-Host "ResourceGraph module is installed, continue." }
else {
    Write-Host "ResourceGraph module not found, installing."
    Install-Module -Name Az.ResourceGraph
}

Write-Host "Connecting to Azure."
Connect-Azure("company-devnetops-test")

$excludeList = Get-Content .\subsystem\ExcludeFQDN.lst
Write-Host "These certs will be excluded from notifications:"
$excludeList

$pageSize = 100
$iteration = 0
$searchParams = @{
    Query = 'where type =~ "Microsoft.Network/applicationGateways" | project id, subscriptionId, resourceGroup, name, sslCertificates = properties.sslCertificates | order by id'
    #Query = 'where type =~ "Microsoft.Network/applicationGateways" '
    First = $pageSize
    #Include = 'displayNames'
}

Write-Host "Get data from Azure."
$results = do {
    $iteration += 1
    Write-Verbose "Iteration #$iteration"
    $pageResults = Search-AzGraph @searchParams
    $searchParams.Skip += $pageResults.Count
    $pageResults
    Write-Verbose $pageResults.Count
} while ($pageResults.Count -eq $pageSize)

$AppGwCounter=0
$numberOfAppGws=0
$certificateCounter=0
$expiredCertificateCounter=0
$almostExpiredCertificateCounter=0
$excludedCertificateCounter=0
$expiredCertificateCollection = @()
$almostExpiredCertificateCollection = @()
$excludedCertificateCollection = @()

$daysFromNow = (Get-Date).AddDays($ExpiresInDays)

$results | ForEach-Object { $numberOfAppGws++ }

Write-Host "Analysing results..." #–NoNewline
$date=Get-Date
$results | ForEach {
    $record = $_
    
    $AppGwCounter++
    $completePercent = $AppGwCounter/$numberOfAppGws * 100
    Write-Progress -Activity "Analysing results." -PercentComplete $completePercent -Status "Checking $AppGwCounter of $numberOfAppGws."
    
    $record.sslCertificates | ForEach {
        $sslCertRecord = $_
        $certificateCounter++
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]([System.Convert]::FromBase64String($_.properties.publicCertData.Substring(60,$_.properties.publicCertData.Length-60)))
        $dublicate = $false
        
        #"This cert is valid till"      ## This was just testing, can be removed
        #$cert.NotAfter.DateTime    
        #$daysFromNow.DateTime

        (New-TimeSpan -Start $date -End $cert.NotAfter).Days

        if ($cert.NotAfter -le $daysFromNow) {
            $validDays = New-TimeSpan -Start $date -End $cert.NotAfter
            $subscriptionName = Get-AzSubscription -SubscriptionId $record.subscriptionId | Select-Object -ExpandProperty Name

            $thisAccount = Get-AzureAccounts -singleAccountId $subscriptionName
            $customerAccountName = ([PSCustomObject]$thisAccount.Name)
            $email = Get-HecProjectLeadEmail -customerName $customerAccountName

            if ($sslCertRecord.properties.httpListeners) { $inUse = $true }
            else { $inUse = $false }

            #$criticalCertificate= @{DomainName=($cert.Subject.Split(',')[0]).Substring(3);ValidDays=$validDays.Days;AzureAccount=$record.subscriptionDisplayName;Name=$sslCertRecord.name}
            $criticalCertificate= @{DomainName=($cert.Subject.Split(',')[0]).Substring(3);ValidDays=$validDays.Days;AzureAccount=$subscriptionName;CertName=$sslCertRecord.name;InUse=$inUse;AppGw=$record.name;Email=$email;CustomerName=$customerAccountName}

            if ($excludeList -contains ($cert.Subject.Split(',')[0]).Substring(3)) {
                $excludedCertificateCollection | ForEach-Object {
                    if($_['Name'] -like $criticalCertificate.Name){
                        Write-Verbose "Already in the list."
                        $dublicate = $true
                        $dublicate | Out-Null
                    }
                }
                if ($dublicate -eq $false) {
                    Write-Verbose "Certificate expired but exluded."
                    $excludedCertificateCounter++
                    $excludedCertificateCollection += $criticalCertificate
                }

            } else {
                $expiredCertificateCollection | ForEach-Object {
                    if($_['DomainName'] -like $criticalCertificate.DomainName){
                        $dublicate = $true
                        $dublicate | Out-Null
                    }
                }
                if ($dublicate -eq $false) {
                    if ($cert.NotAfter -lt (Get-Date)) {
                        Write-Verbose "Already expired."
                        $expiredCertificateCounter++
                        $expiredCertificateCollection += $criticalCertificate
                    }
                    else {
                        Write-Verbose "Expires Soon."
                        $almostExpiredCertificateCounter++
                        $almostExpiredCertificateCollection += $criticalCertificate
                    }
                }
            }
            #$record.Name
            #@($sslCertRecord.properties.httpListeners | ForEach-Object {($_.id -split '/')[-1] })

            $detailsHash = @{
                #SubscriptionId = $record.subscriptionId
                SubscriptionName = $subscriptionName
                ResourceGroup = $record.resourceGroup
                Name = $record.Name
                Cert = $cert.Subject
                CertificateName = $sslCertRecord.name
                NotAfter = $cert.NotAfter
                #Thumbprint = $cert.Thumbprint
                ImpactedListeners = ,@($sslCertRecord.properties.httpListeners | ForEach-Object {($_.id -split '/')[-1] })
            }
            foreach($key in $detailsHash.Keys){Write-Verbose "$key $($detailsHash[$key])"}

            #sendAlertEmail -alertedUser $mailTo -customer $record.resourceGroup -certificate $sslCertRecord.name
            #Read-Host -Prompt "Continue ?"
        }
    }
}
Write-Host ""
Write-Host "Expiring soon:"
$almostExpiredCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize
Write-Host "Expired already:"
$expiredCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize
Write-Host "Exluded:"
$excludedCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize

$path= $env:userprofile + "\Downloads\ExpiringCertificates_Azure.txt"
$almostExpiredCertificateCollection | Out-File -FilePath $path
$expiredCertificateCollection | Out-File -FilePath $path -Append
$excludedCertificateCollection | Out-File -FilePath $path -Append

Measure-ScriptTiming -startTime ($startTime + $userInputTime)
#$endTime=get-Date
#$runtime = New-TimeSpan -Start $startTime -End $endTime
#Write-Host "The query ran for" $runtime.Hours "hour," $runtime.Minutes "minutes and" $runtime.Seconds "seconds."

Write-Host "Found" $almostExpiredCertificateCounter "certificates that will expire in less than" $ExpiresInDays "days."
Write-Host "Found" $expiredCertificateCounter "certificates that have expired in the past."
Write-Host "Found" $excludedCertificateCounter "certificates that have been excluded."
Write-Host "Found" $certificateCounter "certificates in total across" $AppGwCounter "Application Gateways."

$userInput = Read-Host -Prompt "Do you want to send email reminders ? (y/n)"
if ($userInput -eq "y") {
    $almostExpiredCertificateCollection | ForEach-Object {
        #Write-Output "Sending email." $_.Email $_.CustomerName $_.ValidDays $_.DomainName
        if ( $_.Email -ne "Check customer manually." -and $_.Email -ne "Check email manually." -and $_.InUse -eq $true ) {
            Write-Host "AlertedUser:" $_.Email " ;Customer:" $_.CustomerName " ;ExpiringDate:" $_.ValidDays " ;Certificate:" $_.DomainName
            Send-AlertEmail -alertedUser $_.Email -customer $_.CustomerName -expiringDate $_.ValidDays -certificate $_.DomainName
        }
        else {
            Write-Host "No email found for" $_.CustomerName
        }
    }
}

$VerbosePreference = $oldverbose
