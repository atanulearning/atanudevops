## Includes ###########################################################################################

$ErrorActionPreference = "stop"                     # Stop script on error encounter
#. .\subsystem\Measure-ScriptTiming.ps1 # Save timing and show avarage.

## Part I: Data input #################################################################################

$CommonName = $Env:CommonName 

$CommonName

## Optional input ######################################################################################

$SANs= @()      #ToDo enable SAN support
$passPhrase=""
#$passPhrase = Read-Host -Prompt "Please enter the passPhrase for the key. Press enter to leave blank."
$path = "C:\Certificates\"

## Part II: sanity check ###############################################################################

try {
    openssl version
}
catch {
    Write-Output "Please install openssl and set the PATH system variable to the openssl/bin folder in the advanced system settings. (https://medium.com/swlh/installing-openssl-on-windows-10-and-updating-path-80992e26f6a1)"
    Return -1
}

## Part III: logic #####################################################################################

$startTime = Get-Date
$timeUserInput = New-TimeSpan

$currentPath = get-location
Set-Location $path

$csrName = ($CommonName -replace "\*","star") +".csr"
$keyName = ($CommonName -replace "\*","star") +".key"

if (test-path -Path ./xyz.cnf) {
    Remove-Item -Path ./xyz.cnf
}

New-Item -Path ./XYZ.cnf -ItemType File
Add-Content ./XYZ.cnf "[ req ]"
Add-Content ./XYZ.cnf "default_bits       = 2048"
Add-Content ./XYZ.cnf "distinguished_name = req_distinguished_name"
Add-Content ./XYZ.cnf "req_extensions     = req_ext"
Add-Content ./XYZ.cnf "[ req_distinguished_name ]"
Add-Content ./XYZ.cnf "C = DE"
Add-Content ./XYZ.cnf "ST = Baden-Wuerttemberg"
Add-Content ./XYZ.cnf "L = Walldorf"
Add-Content ./XYZ.cnf "O = Cloud Managed Services"
Add-Content ./XYZ.cnf ("CN = "+$CommonName)
Add-Content ./XYZ.cnf "[ req_ext ]"
Add-Content ./XYZ.cnf "subjectAltName = @alt_names"
Add-Content ./XYZ.cnf "[alt_names]"
Add-Content ./XYZ.cnf ("DNS.1   = DNS:"+$CommonName)

if ((test-path -Path ./$csrName) -or (test-path -Path ./$keyName)) {
    $timeUserInputStart=Get-Date
    Write-Output ""
    do {
        $userInput = Read-Host -Prompt "A file for this FQDN exists already. Do you want to continue ? (y/n)"
        if ($userInput -eq "y") {
            Write-Output "Continue."
        } elseif ($userinput -eq "n") {
            Write-Output "Aborted."
            Set-Location $currentPath
            exit
        }
    } while ($userinput -ne "y" -and $userinput -ne "n")
    $timeUserInput = New-TimeSpan $timeUserInputStart (Get-Date)
}

if ($passPhrase -eq "") { ## No password provided.
    $command=" req -new -newkey rsa:2048 -nodes -keyout "+$keyName+" -out "+$csrName+" -subj `"/C=DE/ST=Baden-Wuerttemberg/L=Walldorf/O=XYZ/OU=Cloud Managed Services/emailAddress=mc-devnetops@groups.XYZ.com/CN="+$CommonName+"`" -config XYZ.cnf"
}
else { ## Password provided.
    $command=" req -new -newkey rsa:2048 -sha256 -passout pass:"+$passPhrase+"-keyout "+$keyName+" -out "+$csrName+" -subj `"/C=DE/ST=Baden-Wuerttemberg/L=Walldorf/O=XYZ/OU=Cloud Managed Services/emailAddress=mc-devnetops@groups.XYZ.com/CN="+$CommonName+"`" -config XYZ.cnf"
    #$command=" req -new -newkey rsa:2048 -sha256 -passout pass:"+$passPhrase+"-keyout "+$keyName+" -out "+$csrName+" -config XYZ.cnf"
}
$command
try {
    $command | openssl 
    #Compress-Archive -Force -Path ./$csrName -DestinationPath ./$csrName".zip"
    Compress-Archive -Force -Path ./$keyName -DestinationPath ./$keyName".zip"
    #Remove-Item -Path ./$csrName
    #Remove-Item -Path ./$keyName
}
finally {
    Set-Location $currentpath
}

#Measure-ScriptTiming -startTime ($startTime+$timeUserInput)

Write-Host ""
Write-Host "The files have ben saved in" $path
Write-Host "Go to https://www.digicert.com/login"
Write-Host "Add additional email mc-devnetops@groups.XYZ.com"
