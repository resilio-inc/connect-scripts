# RslConnect Toolkit Check Script
[CmdletBinding()]
param(
    [switch]$RunAsSystem,
    [string]$Config = "Config",
    [switch]$SystemExecution,
    [string]$ScriptRoot = $PSScriptRoot,
    [string]$ScriptPath = $PSCommandPath
)

function New-CheckResult 
{
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [ValidateSet("PASS", "FAIL", "WARNING", "INFO")]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Detail
    )

    [PSCustomObject]@{
        Check  = $Check
        Status = $Status
        Detail = $Detail
    }
}

function Write-ReportEntries
{
    param(
        [string]$ReportPath,
        [object[]]$Entries
    )

    if (-not $Entries -or $Entries.Count -eq 0) 
    {
        return
    }

    $tableText = $Entries | Format-Table -AutoSize | Out-String
    Add-Content -LiteralPath $ReportPath -Value $tableText
}

function Write-ReportSummary
{
    param(
        [string]$ReportPath,
        [object[]]$Failures
    )

    Add-Content $ReportPath ""
    Add-Content $ReportPath "=== Summary ==="

    if ($Failures.Count -eq 0) {

        $summary = @(
            New-CheckResult `
                -Check "General" `
                -Status PASS `
                -Detail "All checks passed."
        )
    }
    else {
        $summary = $Failures
    }

    Write-ReportEntries `
        -ReportPath $ReportPath `
        -Entries $summary

    Write-Host ""

    if ($Failures.Count -eq 0) 
    {
        Write-Host "All checks passed." -ForegroundColor Green
    }
    else
    {
        Write-Host "Failed checks:" -ForegroundColor Red
        $Failures | Format-Table -AutoSize
    }

    Write-Host ""
    Write-Host "Report created: $ReportPath" -ForegroundColor Cyan
}

function Get-Config
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot,
        [Parameter(Mandatory = $true)]
        [string]$ConfigName
    )

    $resolvedConfigPath = Join-Path -Path $ScriptRoot -ChildPath "$ConfigName.json"

    Write-Host "Using config file: $resolvedConfigPath" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $resolvedConfigPath))
    {
        throw "Config file not found at $resolvedConfigPath"
    }

    $config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
    if (-not $config.Checks)
    {
        throw "Config file must contain a Checks object."
    }

    return $config
}

function Invoke-ConfiguredChecks
{   
	param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot,
        [Parameter(Mandatory = $true)]
        [string]$ConfigName
	)

    Write-Host "Running identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

    $config = Get-Config -ScriptRoot $ScriptRoot -ConfigName $ConfigName
	$reportsPath = Join-Path -Path $ScriptRoot -ChildPath "Reports"

	if (-not (Test-Path -LiteralPath $reportsPath))
    {
		New-Item -Path $reportsPath -ItemType Directory | Out-Null
	}

	$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
	$reportPath = Join-Path -Path $reportsPath -ChildPath ("Report_{0}.txt" -f $timestamp)

	$settingsText = $config | ConvertTo-Json -Depth 10
	$headerLines = @(
		"=== Settings ===",
		$settingsText,
		"",
		"=== Checks ==="
	)
	Set-Content -LiteralPath $reportPath -Value $headerLines

	$enabledChecks = @(
        $config.Checks.PSObject.Properties |
        Where-Object Value -eq $true
    )

    $failures = @()

    foreach ($check in $enabledChecks)
    {
        $checkName = $check.Name
        $functionName = "Invoke-RslCheck$checkName"

        # In single-file mode check functions are already in memory
        $command = Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue

        if (-not $command)
        {
            # In standalone mode load from module files
            $modulePath = Join-Path $ScriptRoot "Modules\RslCheck-$checkName.psm1"

            if (-not (Test-Path -LiteralPath $modulePath))
            {
                $failure = New-CheckResult `
                    -Check $checkName `
                    -Status FAIL `
                    -Detail "Module not found: $modulePath"

                Write-ReportEntries -ReportPath $reportPath -Entries @($failure)
                $failures += $failure
                continue
            }

            Import-Module $modulePath -Force -ErrorAction Stop
            $command = Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue
        }

        if (-not $command)
        {
            $failure = New-CheckResult `
                -Check $checkName `
                -Status FAIL `
                -Detail "Function '$functionName' not found."

            Write-ReportEntries -ReportPath $reportPath -Entries @($failure)
            $failures += $failure
            continue
        }

        try
        {
            $moduleResults = @(
                & $functionName -Config $config 
            )

            if ($moduleResults.Count -eq 0)
            {
                $moduleResults = @(
                    New-CheckResult `
                        -Check $checkName `
                        -Status FAIL `
                        -Detail "Module returned no results."
                )
            }
        }
        catch
        {
            $moduleResults = @(
                New-CheckResult `
                    -Check $checkName `
                    -Status FAIL `
                    -Detail $_.Exception.Message
            )
        }

        Write-ReportEntries `
            -ReportPath $reportPath `
            -Entries $moduleResults

        foreach ($result in $moduleResults)
        {
            if ($result.Status -eq "FAIL")
            {
                $failures += $result
            }
        }
    }

    Write-ReportSummary -ReportPath $reportPath -Failures $failures
    Add-Content $ReportPath ""
}

function Start-AsSystem 
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    if (-not $IsWindows)
    {
        throw "-RunAsSystem is supported only on Windows."
    }

    if (-not (Test-Path -LiteralPath $ScriptPath))
    {
        throw "Script was not found: $ScriptPath"
    }

    $taskName = "RslConnectToolkit-RunAsSystem"

    # PowerShell arguments for the child process
    $psArgs = @(
        "-NoProfile"
        "-ExecutionPolicy Bypass"
        "-File `"$ScriptPath`""
    ) -join " "

    try
    {
        # Remove previous task if it exists
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
        {
            Unregister-ScheduledTask `
                -TaskName $taskName `
                -Confirm:$false
        }

        $action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument $psArgs

        $principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

        $task = New-ScheduledTask `
            -Action $action `
            -Principal $principal `
            -Settings $settings

        Register-ScheduledTask `
            -TaskName $taskName `
            -InputObject $task `
            -Force | Out-Null

        Write-Host "Starting '$taskName' as NT AUTHORITY\SYSTEM..." -ForegroundColor Cyan

        Start-ScheduledTask -TaskName $taskName

        # Wait until task finishes
        do
        {
            Start-Sleep -Seconds 1

            $state = (
                Get-ScheduledTask `
                    -TaskName $taskName
            ).State
        }
        while ($state -eq "Running")

        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName

        if ($taskInfo.LastTaskResult -ne 0)
        {
            throw "SYSTEM task failed. Exit code: $($taskInfo.LastTaskResult)"
        }

        Write-Host "SYSTEM execution completed successfully." -ForegroundColor Green
    }
    finally
    {
        # Always cleanup
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
        {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
    }
}

function Invoke-RslCheck
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Config,
        [switch]$RunAsSystem,
        [switch]$SystemExecution,
        [string]$ScriptRoot = $PSScriptRoot,
        [string]$ScriptPath = $PSCommandPath
    )

    # Clear any previously loaded RslCheck modules and functions to avoid conflicts
    Get-Module RslCheck-* | Remove-Module -Force
    Get-ChildItem Function:Invoke-RslCheck* | Remove-Item -Force

    # Ensure ScriptRoot and ScriptPath are set correctly    
    if ([string]::IsNullOrWhiteSpace($ScriptRoot))
    {
        $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }

    if ([string]::IsNullOrWhiteSpace($ScriptPath))
    {
        $ScriptPath = $MyInvocation.MyCommand.Path
    }

    if ($RunAsSystem -and -not $SystemExecution)
    {
        Start-AsSystem -ScriptPath $ScriptPath
        exit 0
    }

    Write-Host "=================================="
    Write-Host "RslConnect Check"
    Write-Host "=================================="
    Write-Host ""

    Invoke-ConfiguredChecks -ScriptRoot $ScriptRoot -ConfigName $Config
}

if ($MyInvocation.MyCommand.Name -eq "Check.ps1")
{
    Invoke-RslCheck `
        -Config $Config `
        -RunAsSystem:$RunAsSystem `
        -SystemExecution:$SystemExecution `
        -ScriptRoot $ScriptRoot `
        -ScriptPath $ScriptPath
}
