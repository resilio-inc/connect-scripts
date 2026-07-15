# RslConnect Toolkit Setup Script
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NassuniServer
)

function Install-RslPrerequisites
{
    if (Get-Command Get-ADComputer -ErrorAction SilentlyContinue)
    {
        Write-Host "Active Directory tools are already available." -ForegroundColor Yellow
        return
    }

    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $isServerOS = $osInfo.ProductType -ne 1

    if ($isServerOS)
    {
        Write-Host "Detected Windows Server. Installing RSAT-AD-PowerShell feature..."
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
    }
    else
    {
        $capabilityName = "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
        Write-Host "Detected Windows Client. Installing RSAT capability $capabilityName..."

        $capability = Get-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop
        if ($capability.State -ne "Installed")
        {
            Add-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop | Out-Null
        }
    }

    if (-not (Get-Command Get-ADComputer -ErrorAction SilentlyContinue))
    {
        throw "Active Directory PowerShell tools were not detected after installation. Run as Administrator and try again."
    }
}

function Set-RslSPN
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $Spn1 = "rslmc/$ComputerName.$Domain"
    $Spn2 = "rsl/$ComputerName.$Domain"
    $ComputerAccount = "$ComputerName`$"
    $Command1 = "setspn -S `"$Spn1`" `"$ComputerAccount`""
    $Command2 = "setspn -S `"$Spn2`" `"$ComputerAccount`""

    Write-Host "SPN configuration summary"
    Write-Host "  Server account being updated (controlled object): $ComputerAccount"
    Write-Host "  SPNs to add (trusted service identifiers):"
    Write-Host "    - $Spn1"
    Write-Host "    - $Spn2"
    Write-Host ""
    Write-Host "Commands to run (copy/paste):" -ForegroundColor Cyan
    Write-Host "  $Command1" -ForegroundColor Gray
    Write-Host "  $Command2" -ForegroundColor Gray
    Write-Host ""

    if (Read-RslYesNo -Prompt "Apply SPN changes now?" -DefaultYes $true)
    {
        Write-Host "Applying SPN commands..."
        setspn -S $Spn1 $ComputerAccount
        setspn -S $Spn2 $ComputerAccount
    }
    else
    {
        Write-Host "Skipped SPN configuration by user choice. Use the commands above when ready." -ForegroundColor Yellow
    }
}

function Enable-RslDelegation
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [Parameter(Mandatory = $true)]
        [string]$NassuniServer
    )

    $PrimaryAgentAccount = Get-ADComputer -Identity $ComputerName -ErrorAction Stop
    $GetPrimaryAgentCommand = "Get-ADComputer -Identity `"$ComputerName`" -ErrorAction Stop"
    $DelegationCommand = "Set-ADComputer -Identity `"$NassuniServer`" -PrincipalsAllowedToDelegateToAccount @($GetPrimaryAgentCommand)"

    Write-Host "Delegation configuration summary"
    Write-Host "  Controlled resource computer (service you protect): $NassuniServer"
    Write-Host "  Trusted delegating computer (allowed principal): $($PrimaryAgentAccount.Name)"
    Write-Host ""
    Write-Host "Command to run (copy/paste):" -ForegroundColor Cyan
    Write-Host "  $DelegationCommand" -ForegroundColor Gray
    Write-Host ""

    if (Read-RslYesNo -Prompt "Apply delegation now?" -DefaultYes $true)
    {
        Write-Host "Applying delegation command..."
        Set-ADComputer `
            -Identity $NassuniServer `
            -PrincipalsAllowedToDelegateToAccount @($PrimaryAgentAccount)
    }
    else
    {
        Write-Host "Skipped delegation by user choice. Use the command above when ready." -ForegroundColor Yellow
    }
}

function Read-RslYesNo
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }

    while ($true)
    {
        $answer = Read-Host "$Prompt $suffix"

        if ([string]::IsNullOrWhiteSpace($answer))
        {
            return $DefaultYes
        }

        switch ($answer.Trim().ToLowerInvariant())
        {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Host "Please answer y or n." -ForegroundColor Yellow }
        }
    }
}

function Invoke-RslSetup
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NassuniServer
    )

    $ComputerName = $env:COMPUTERNAME
    $Domain = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Domain

    Write-Host "=================================="
    Write-Host "RslConnect Setup Wizard"
    Write-Host "=================================="
    Write-Host "Detected computer: $ComputerName"
    Write-Host "Detected domain:   $Domain"
    Write-Host ""

    Write-Host "[1/3] Configuring SPN..."
    Write-Host ""

    Set-RslSPN -ComputerName $ComputerName -Domain $Domain
    Write-Host "OK"
    Write-Host ""

    Write-Host "[2/3] Installing prerequisites..."
    Write-Host ""

    Install-RslPrerequisites
    Write-Host "OK"
    Write-Host ""

    Write-Host "[3/3] Configuring delegation..."
    Write-Host ""

    Enable-RslDelegation -ComputerName $ComputerName -NassuniServer $NassuniServer
    Write-Host "OK"
    Write-Host ""

    Write-Host "Setup completed successfully." -ForegroundColor Green
}

if ($MyInvocation.MyCommand.Name -eq "Setup.ps1")
{
    Invoke-RslSetup -NassuniServer $NassuniServer
}
