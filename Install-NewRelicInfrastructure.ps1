<#
.SYNOPSIS
    Runbook to install New Relic Infrastructure Client using a hybrid worker.

.DESCRIPTION
    This runbook makes a clean install of the New Relic infrastructure client, updates it with a product key and then restarts the service

.PARAMETER NewRelicClientUrl
    Url to the new relic infrastructure client. The officielt file is default.

.PARAMETER InstallDir
    Directory where the client should be installed. Default is C:\Program Files\New Relic

.PARAMETER NewRelicKey
    Your license key for the new relic client

.PARAMETER Computers
    The list of computers you need to install the client on. Split using ","
#>

param (
    [Parameter()][string]$NewRelicClientUrl = "https://download.newrelic.com/infrastructure_agent/windows/newrelic-infra.msi",
    [Parameter()][string]$InstallDir = "C:\Program Files\New Relic\",
    [Parameter(Mandatory=$true)][string]$NewRelicKey,
    [Parameter(Mandatory=$true)][string]$Computers,
    [Parameter(Mandatory=$true)][string]$Credentials
    
)

#Getting credentials from Azure Automation
$vmCred = Get-AutomationPSCredential -Name $Credentials

#Options when running the invoke
$vmOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck

#Getting list of computers
if($Computers.Contains(",")) {
    [string[]]$ComputersToInstall = $Computers.Split(",")
}
else {
    [string[]]$ComputersToInstall = $Computers
}

#Looping through every computer we need to install it on.
foreach($Computer in $ComputersToInstall)
{
    Write-Output "Working on $Computer"

    #Check if SSL is possible - else try without
    if(Test-WSMan -ComputerName $Computer) {
        $sslFlag = $false
    }
    else {
        $sslFlag = $true
    }

    #Running the script
    Invoke-Command -ComputerName $Computer -SessionOption $vmOptions -UseSSL:$sslFlag -Credential $vmCred -ArgumentList $NewRelicClientUrl, $InstallDir, $NewRelicKey  -ScriptBlock {
        #Getting the parameters
        param ($NewRelicClientUrl, $InstallDir, $NewRelicKey)

        #Downloading New Relic client
        Write-Output "Downloading New Relic Client"
        $File = "$env:temp\newrelic-infra.msi"

        #Downloading the file
        (New-Object System.Net.WebClient).DownloadFile($NewRelicClientUrl, $File)   
        Write-Output "Downloaded to: $File"

        #Installing client
        Write-Output "Installing Client"
        Start-Process msiexec.exe -Wait -ArgumentList "/I `"$File`" TARGETDIR=`"$InstallDir`" /qn"
        Write-Output "Client Installed"

        #Updating license file
        Write-Output "Updating License file"
        (Get-Content "$InstallDir\newrelic-infra\newrelic-infra.yml").Replace("<ENTER YOUR NEW RELIC KEY HERE>", $NewRelicKey) | Set-Content "$InstallDir\newrelic-infra\newrelic-infra.yml"

        #Wait a bit to get the service registered properly
        Start-Sleep 5

        #Restarting service
        Get-Service -Name newrelic-infra | Restart-Service

        #Cleaning up
        Write-Output "Cleaning up"
        Remove-Item $File -Force
    } -ErrorVariable errors

    if($errors) {
        Write-Output "Something went wrong - " $errors | Format-List
    }
    $errors = ""
}