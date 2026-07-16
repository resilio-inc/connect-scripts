# RslConnect Toolkit Setup Script
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NasuniShare,
    [Parameter()]
	[string]$PrimaryAgent
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
        [string]$PrimaryAgent,
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $SpnMc = "rslmc/$ComputerName.$Domain"
    $SpnAgent = "rsl/$PrimaryAgent.$Domain"
    $ComputerAccount = "$ComputerName`$"
    $PrimaryAgentAccount = "$PrimaryAgent`$"
    $Command1 = "setspn -S `"$SpnMc`" `"$ComputerAccount`""
    $Command2 = "setspn -S `"$SpnAgent`" `"$PrimaryAgentAccount`""

    Write-Host "SPN configuration summary"
    Write-Host "  Server account being updated (controlled object): $ComputerAccount"
    Write-Host "  Primary agent account being updated (controlled object): $PrimaryAgentAccount"
    Write-Host "  SPNs to add (trusted service identifiers):"
    Write-Host "    - $SpnMc"
    Write-Host "    - $SpnAgent"
    Write-Host ""
    Write-Host "Commands to run (copy/paste):" -ForegroundColor Cyan
    Write-Host "  $Command1" -ForegroundColor Gray
    Write-Host "  $Command2" -ForegroundColor Gray
    Write-Host ""

    if (Read-RslYesNo -Prompt "Apply SPN changes now?" -DefaultYes $true)
    {
        Write-Host "Applying SPN commands..."
        setspn -S $SpnMc $ComputerAccount
        setspn -S $SpnAgent $PrimaryAgentAccount
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
        [string]$NasuniShare,
        [Parameter(Mandatory = $true)]
        [string]$PrimaryAgent
    )

    Test-ActiveDirectoryConnectivity

    $PrimaryAgentAccount = Get-ADComputer -Identity $PrimaryAgent -ErrorAction Stop
    $GetPrimaryAgentCommand = "Get-ADComputer -Identity `"$PrimaryAgent`" -ErrorAction Stop"
    $DelegationCommand = "Set-ADComputer -Identity `"$NasuniShare`" -PrincipalsAllowedToDelegateToAccount @($GetPrimaryAgentCommand)"

    Write-Host "Delegation configuration summary"
    Write-Host "  Controlled resource computer (service you protect): $NasuniShare"
    Write-Host "  Trusted delegating computer (allowed principal): $($PrimaryAgentAccount.Name)"
    Write-Host ""
    Write-Host "Command to run (copy/paste):" -ForegroundColor Cyan
    Write-Host "  $DelegationCommand" -ForegroundColor Gray
    Write-Host ""

    if (Read-RslYesNo -Prompt "Apply delegation now?" -DefaultYes $true)
    {
        Write-Host "Applying delegation command..."
        Set-ADComputer `
            -Identity $NasuniShare `
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

function Test-ActiveDirectoryConnectivity
{
    try
    {
        Get-ADDomain -ErrorAction Stop | Out-Null
    }
    catch
    {
        throw "Cannot contact Active Directory. Verify the computer is domain-joined and a domain controller with AD Web Services is reachable."
    }
}

function Invoke-RslSetup
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NasuniShare,
        [Parameter()]
        [string]$PrimaryAgent = ""
    )

    $ComputerName = $env:COMPUTERNAME
    $Domain = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Domain
    if ([string]::IsNullOrWhiteSpace($PrimaryAgent))
    {
        Write-Host "No `$PrimaryAgent specified. Will use local computer name." -ForegroundColor Yellow
        Write-Host ""

        $PrimaryAgent = $ComputerName
    }

    Write-Host "=================================="
    Write-Host "RslConnect Setup Wizard"
    Write-Host "=================================="
    Write-Host "Nassuni share: $NasuniShare"
    Write-Host "Primary agent: $PrimaryAgent"
    Write-Host "Detected computer: $ComputerName"
    Write-Host "Detected domain:   $Domain"
    Write-Host ""

    Write-Host "[1/3] Configuring SPN..."
    Write-Host ""

    Set-RslSPN -ComputerName $ComputerName -PrimaryAgent $PrimaryAgent -Domain $Domain
    Write-Host "OK"
    Write-Host ""

    Write-Host "[2/3] Installing prerequisites..."
    Write-Host ""

    Install-RslPrerequisites
    Write-Host "OK"
    Write-Host ""

    Write-Host "[3/3] Configuring delegation..."
    Write-Host ""

    Enable-RslDelegation -NasuniShare $NasuniShare -PrimaryAgent $PrimaryAgent
    Write-Host "OK"
    Write-Host ""

    Write-Host "Setup completed successfully." -ForegroundColor Green
}

if ($MyInvocation.MyCommand.Name -eq "Setup.ps1")
{
    Invoke-RslSetup -NasuniShare $NasuniShare -PrimaryAgent $PrimaryAgent
}
