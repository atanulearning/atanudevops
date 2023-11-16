## PART I: Includes ###############################################################

. .\subsystem\Send-AlertEmail.ps1
. .\subsystem\Get-AwsAccounts.ps1
. .\subsystem\Get-companyProjectLeadEmail.ps1
. .\subsystem\Measure-ScriptTiming.ps1

## PART II: Data input ############################################################

$daysTillExpire=60
$singleAccount=""   ## Leave empty "" to gather accounts from webQuery.
$quickMode=$true    ## gets the location from the webquery also.

## PART III: Logic ################################################################

$startTime = get-Date
$time=get-Date -Format HH:mm
$date=get-Date -Format yyyy-M-dd
Write-Host $date $time

$excludeList = Get-Content .\subsystem\ExcludeFQDN.lst

$awsAccountCollection=New-Object -TypeName System.Collections.ArrayList
if ($singleAccount -ne "") { ## If single account is given: replace list.
    $awsAccountCollection = Get-AwsAccounts -singleAccountId $singleAccount
}else {
    Write-Host "Gather AWS account numbers and locations."
    $awsAccountCollection = Get-AwsAccounts   ## Get AWS accounts from web query
}

Write-Host ""
$awsAccountCollectionCounter = $awsAccountCollection.Count
Write-Host "This script will go over all" $awsAccountCollectionCounter "AWS subscriptions and show a list of certificates that will expire soon."


$Env:AWS_ACCESS_KEY_ID=""
$Env:AWS_SECRET_ACCESS_KEY=""
$Env:AWS_SESSION_TOKEN=""
"logged in as:"
aws sts get-caller-identity
$accountCounter=0
$certificateCounter=0
$expiredCertificateCounter=0
$almostExpiredCertificateCounter=0
$switchRoleDeniedCounter=0
$manualCheckCertificateCounter=0
$excludedCertificateCounter=0
$expiredCertificateCollection = @()
$almostExpiredCertificateCollection = @()
$switchRoleDeniedCollection = @()
$manualCheckCertificateCollection = @()
$excludedCertificateCollection = @()

$awsAccountCollection | ForEach-Object { ## awsAccountCollection.GetEnumerator()
    $customerAccount=$_
    $accountCounter++
    $certsFound=$false
    $awsAssumeRole="Company_Role_Readonly"
    $awsRoleArn= "arn:aws:iam::"+$customerAccount.AwsNumber+":role/"+$awsAssumeRole ##[0] = .key
    $awsSessionName=$customerAccount.AwsNumber+"_"+$awsAssumeRole ##[0] = .key

    $assumeRole = aws sts assume-role --role-arn $awsRoleArn --role-session-name $awsSessionName | ConvertFrom-Json
    $Env:AWS_ACCESS_KEY_ID=$assumeRole.Credentials.AccessKeyId
    $Env:AWS_SECRET_ACCESS_KEY=$assumeRole.Credentials.SecretAccessKey
    $Env:AWS_SESSION_TOKEN=$assumeRole.Credentials.SessionToken
    $currrentRole = aws sts get-caller-identity | ConvertFrom-Json

    if ($currrentRole.Arn -notlike "arn:aws:iam::85xxxxxx7703:user/xyz_cli_ro_access") { #AWS master account means assume role did not succeed. Go to next account.
        "Assumed role to " + "["+$accountCounter+"/"+$awsAccountCollectionCounter+"]" +":"
        $currrentRole.Arn
        $time=get-Date -Format HH:mm
        
        Write-Host $date $time "Searching for certificates..."
        $regionCollection = aws ec2 describe-regions --region us-east-2 | ConvertFrom-Json ## Get all possible locations.
        $regionCollection.Regions | ForEach-Object {
            $region=$_
            if (($quickMode -eq $true -and $region.RegionName -eq $customerAccount.Location)-or ($quickMode -eq $true -and $regionCollection.Regions.RegionName -notcontains $customerAccount.Location) -or $quickMode -eq $false) { ## [1] = $customerAccount.value
                Write-Verbose ("Searching in " + $region.RegionName +" "+ $customerAccount.Location +" "+ $quickMode)
                $certs = aws acm list-certificates --region $region.RegionName
                if( $certs.count -eq 3 -or $certs -eq $null) {
                    Write-verbose ("No certificates in " + $_.RegionName)
                }else {
                    $certsFound=$true
                    $certsFound | Out-Null # Gives otherwise an error, check why.
                    $numberOfcerts=(($certs.count)-4)/4
                    $certificateCounter+=$numberOfcerts
                    Write-Host "Details of" $numberOfcerts "Certificate(s) in" $region.RegionName ":"
                    $noJcerts= $certs | ConvertFrom-Json
                    $noJcerts.CertificateSummaryList | ForEach-Object {
                        $awscert_arn=$_.CertificateArn
                        Write-Host "Region : " $region.RegionName
                        $certDetails = (aws acm describe-certificate --region $region.RegionName --certificate-arn $awscert_arn) | ConvertFrom-Json
                        if ($certDetails -eq $null) { 
                            $certs #left over troubleshooting.
                        }
                        else {
                            if($certDetails.Certificate.InUseBy) {  $inUse=$true }
                            else {                                  $inUse=$false }

                            Write-Host "In Use : " $inUse
                            Write-Host "Domain : " $certDetails.Certificate.DomainName
                            if($certDetails.Certificate.SubjectAlternativeNames.Length -gt 1) {
                            Write-Host "SAN    : " ($certDetails.Certificate.SubjectAlternativeNames -join "; ")}
                            Write-Host "Subject: " $certDetails.Certificate.Subject
                            Write-Verbose ("Issuer : "+ $certDetails.Certificate.Issuer)
                            Write-Host "Expires: " $certDetails.Certificate.NotAfter
                            if ($certDetails.Certificate.NotAfter) {
                                $validDays = New-TimeSpan -Start $date -End $certDetails.Certificate.NotAfter.Substring(0,10)
                                Write-Host "In days: " $validDays.Days
                            }
                            else {
                                Write-Host "Please check manually as no expiring date was found."
                                $manualCheckCertificateCounter++
                                $manualCheckCertificateCollection += @{DomainName=$certDetails.Certificate.DomainName;ValidDays="n/a";AwsAccount=$customerAccount.AwsNumber;CustomerName=$customerAccount.Name;Email=$email;InUse=$inUse}
                            }
                            if ($validDays.Days -lt $daysTillExpire) {
                                $email = Get-HecProjectLeadEmail -customerName ($customerAccount.Name)
                                $criticalCertificate= @{DomainName=$certDetails.Certificate.DomainName;ValidDays=$validDays.Days;AwsAccount=$customerAccount.AwsNumber;CustomerName=$customerAccount.Name;Email=$email;InUse=$inUse}
                                if ($excludeList -contains $certDetails.Certificate.DomainName) {
                                    Write-Host "Certificate expired but exluded."
                                    $excludedCertificateCounter++
                                    $excludedCertificateCollection += $criticalCertificate
                                } else {
                                    if ($validDays.Days -lt 0) {
                                        Write-Host "!!! This certificate expired" $validDays.Days "days ago !!!"
                                        $expiredCertificateCounter++
                                        $expiredCertificateCollection += $criticalCertificate
                                    }
                                    else {
                                        Write-Host "!! This certificate expires in less than" $daysTillExpire "days !!"
                                        $almostExpiredCertificateCounter++
                                        $almostExpiredCertificateCollection += $criticalCertificate
                                    } 
                                }
                            }
                            Write-Host "" 
                        }
                    }
                }
            }
        }
        if ($certsFound -eq $false) { Write-Host "No certificates found for the customer." }
        else { Write-Verbose ("Certificate(s) found."+$certsFound) }
        $Env:AWS_ACCESS_KEY_ID=""
        $Env:AWS_SECRET_ACCESS_KEY=""
        $Env:AWS_SESSION_TOKEN=""
        ""
    }
    else {
        $switchRoleDeniedCounter++
        $switchRoleDeniedCollection += $customerAccount.AwsNumber
        Write-Host "Switching role not possible, continue with next account."
        Write-Host ""
    }
}

Write-Host "Expiring soon:"
$almostExpiredCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize
Write-Host "Expired already:"
$expiredCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize
Write-Host "Amazon issued, validation timed out:"
$manualCheckCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize
Write-Host "Exluded:"
$excludedCertificateCollection | ForEach-Object {[PSCustomObject]$_} | Format-Table -AutoSize

$path= $env:userprofile + "\Downloads\ExpiringCertificates_AWS.txt"
$almostExpiredCertificateCollection | Out-File -FilePath $path
$expiredCertificateCollection | Out-File -FilePath $path -Append
$manualCheckCertificateCollection | Out-File -FilePath $path -Append
$excludedCertificateCollection | Out-File -FilePath $path -Append

Measure-ScriptTiming -startTime ($startTime + $userInputTime)
#$endTime=get-Date
#$runtime = New-TimeSpan -Start $startTime -End $endTime
#Write-Host ""
#Write-Host "The query ran for" $runtime.Hours "hour," $runtime.Minutes "minutes and" $runtime.Seconds "seconds."

Write-Host "Found" $almostExpiredCertificateCounter "certificates that will expire in less than" $daysTillExpire "days."
Write-Host "Found" $expiredCertificateCounter "certificates that have expired in the past."
Write-Host "Found" $manualCheckCertificateCounter "certificates without expiration date."
Write-Host "Found" $excludedCertificateCounter "certificates that have been excluded."
Write-Host "Found" $certificateCounter "certificates in total across" $accountCounter "accounts."

Write-Verbose ("Unable to login to"+$switchRoleDeniedCounter+"account(s).")
$switchRoleDeniedCollection | ForEach-Object { Write-Verbose $_}

Write-Host ""
Write-Host "Emails"
ForEach ($certEntry in $almostExpiredCertificateCollection) {
    Write-Host "Email for customer: " $certEntry.CustomerName ":" $email
    Send-AlertEmail -alertedUser $email -customer $certEntry.CustomerName -expiringDate $certEntry.ValidDays -certificate $certEntry.DomainName
}
