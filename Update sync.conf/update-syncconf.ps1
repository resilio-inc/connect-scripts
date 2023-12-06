<#	
.SYNOPSIS
Modify sync.conf file of Resilio Connect Agent

.DESCRIPTION
Modify sync.conf file by autodetected or specified path. Script can adjust
standard parameters (storage path, fingerprint, host, bootstrap token) as
well as add / modify custom parameters (use_gui, device_name, etc.)
Script requires elevated privileges if your sync.conf stays in Program Files
directory.
Actual directory where script arrives does not matter. 

.PARAMETER SyncConfPath
Specifies path to sync.conf file including sync.conf. If not specified, script
will access the registry to find Agent installation path and sync.conf location

.PARAMETER NewBootstrap
Specifies new bootstrap token you want to get into your sync.conf

.PARAMETER NewHost
Specifies new host and port value (colon separated) to be set into your sync.conf

.PARAMETER NewFingerprint
Specifies new server certificate fingerprint to be set into your sync.conf

.PARAMETER NewStoragePath
Specifies new storage path to be set into your sync.conf

.PARAMETER DisableCertCheck
Sets parameter in the sync.conf that forces agent to skip MC certificate verification

.PARAMETER EnableCertCheck
Sets parameter in the sync.conf that forces agent to conduct MC certificate verification

.PARAMETER CustomParameterName
Specifies custom parameter name to be inserted / changed into your sync.conf

.PARAMETER CustomParameterValue
Specifies custom parameter value which will be set into your sync.conf

.PARAMETER RemoveCustomParameter
Set this if you want to delete custom parameter from sync.conf

.PARAMETER EnableAgentUI
Set this if you want to enable Agent UI. Agent must be restarted for
change to take effect. You can use RestartAgent switch in the same
call to both enable UI and restart agent.

.PARAMETER CreateAgentUIShortcut
Set this if you want to get Agent UI shortcut on user's desktop

.PARAMETER AutorunAgentUI
Set this if you want automatically start agent UI when user logs in.

.PARAMETER RestartAgent
Set this if you want script to restart agent service after changing 
sync.conf. Script will use Windows Task Scheduler to call itself with
PerformGracefulRestart switch set. Recommended if you call the script 
from any of Resilio Connect jobs.

.PARAMETER PerformGracefulRestart
Performs actual restart of the agent service. It's not recommended to call
this method if you run the script from Agent itself (via job). Use
RestartAgent instead. Agent restart is timeoutless and script will wait 
agent service to shut down as long as it needed even if service control
timeouts. After service moves to "Stopped" state, script will start it again.

.EXAMPLE
update-syncconf.ps1 -CustomParameterName "device_name" -CustomParameterValue "%TAG_AGENT_NAME%"

.EXAMPLE
update-syncconf.ps1 -EnableAgentUI -CreateAgentUIShortcut -AutorunAgentUI -RestartAgent
#>

Param (
	[Parameter(ParameterSetName = 'changestandard')]
	[Parameter(ParameterSetName = 'addcustom')]
	[Parameter(ParameterSetName = 'removecustom')]
	[Parameter(ParameterSetName = 'operateui')]
	[string]$SyncConfPath,
	[Parameter(ParameterSetName = 'changestandard')]
	[string]$NewBootstrap,
	[Parameter(ParameterSetName = 'changestandard')]
	[string]$NewHost,
	[Parameter(ParameterSetName = 'changestandard')]
	[string]$NewFingerprint,
	[Parameter(ParameterSetName = 'changestandard')]
	[string]$NewStoragePath,
	[Parameter(ParameterSetName = 'changestandard')]
	[switch]$DisableCertCheck,
	[Parameter(ParameterSetName = 'changestandard')]
	[switch]$EnableCertCheck,
	[Parameter(ParameterSetName = 'addcustom')]
	[Parameter(ParameterSetName = 'removecustom')]
	[string]$CustomParameterName,
	[Parameter(ParameterSetName = 'addcustom')]
	[string]$CustomParameterValue,
	[Parameter(ParameterSetName = 'removecustom')]
	[switch]$RemoveCustomParameter,
	[Parameter(ParameterSetName = 'operateui')]
	[switch]$EnableAgentUI,
	[Parameter(ParameterSetName = 'operateui')]
	[switch]$CreateAgentUIShortcut,
	[Parameter(ParameterSetName = 'operateui')]
	[switch]$AutorunAgentUI,
	[Parameter(ParameterSetName = 'changestandard')]
	[Parameter(ParameterSetName = 'addcustom')]
	[Parameter(ParameterSetName = 'removecustom')]
	[Parameter(ParameterSetName = 'operateui')]
	[switch]$RestartAgent,
	[Parameter(ParameterSetName = 'gracefulrestart')]
	[switch]$PerformGracefulRestart
)

function Create-AgentShortcut()
{
	Param
	(
		[string]$PathToShortcut
	)
	
	$AgentInstallPath = (Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\').InstallDir
	$AgentExePath = Join-Path -Path $AgentInstallPath -ChildPath 'Resilio Connect Agent.exe'
	
	$AgentUIShortcutPath = Join-Path -Path $PathToShortcut -ChildPath "Resilio Connect Agent UI.lnk"
	
	$WshShell = New-Object -comObject WScript.Shell
	$AgentShortcut = $WshShell.CreateShortcut($AgentUIShortcutPath)
	$AgentShortcut.TargetPath = $AgentExePath
	$AgentShortcut.Save()
	
}
# --------------------------------------------------------------------------------------------------------------------------------

$xmlpart1 = '<?xml version="1.0" encoding="UTF-16"?>
		<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
		<RegistrationInfo>
		<Date>2018-11-02T23:15:32</Date>
		<Author>ResilioInc</Author>
		<URI>\ResilioUpgrade</URI>
		</RegistrationInfo>
		<Triggers>
		<TimeTrigger>
		<StartBoundary>1910-01-01T00:00:00</StartBoundary>
		<Enabled>true</Enabled>
		</TimeTrigger>
		</Triggers>
		<Principals>
		<Principal id="Author">
		<UserId>S-1-5-18</UserId>
		<RunLevel>LeastPrivilege</RunLevel>
		</Principal>
		</Principals>
		<Settings>
		<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
		<DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
		<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
		<AllowHardTerminate>true</AllowHardTerminate>
		<StartWhenAvailable>false</StartWhenAvailable>
		<RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
		<IdleSettings>
		<Duration>PT10M</Duration>
		<WaitTimeout>PT1H</WaitTimeout>
		<StopOnIdleEnd>true</StopOnIdleEnd>
		<RestartOnIdle>false</RestartOnIdle>
		</IdleSettings>
		<AllowStartOnDemand>true</AllowStartOnDemand>
		<Enabled>true</Enabled>
		<Hidden>false</Hidden>
		<RunOnlyIfIdle>false</RunOnlyIfIdle>
		<WakeToRun>false</WakeToRun>
		<ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
		<Priority>7</Priority>
		</Settings>
		<Actions Context="Author">
		<Exec>
		<Command>powershell.exe  </Command>
		<Arguments>-NoProfile -ExecutionPolicy Bypass -File "'

$xmlpart2 = '" -PerformGracefulRestart</Arguments>
		</Exec>
		</Actions>
		</Task>
'
# --------------------------------------------------------------------------------------------------------------------------------
Write-Verbose "Script started"

# Define own paths and names
$ownscriptpathname = $MyInvocation.MyCommand.Definition
$ownscriptpath = Split-Path -Path $ownscriptpathname
$ownscriptname = Split-Path $ownscriptpathname -Leaf

try
{
	if ($PerformGracefulRestart)
	{
		Write-Verbose "Shutting down the agent service and start it again. Gracefully, no pressure"
		Get-Service -Name "connectsvc" | Stop-Service -ErrorAction Continue
		$ServiceStatus = 'Running'
		while ($ServiceStatus -ne 'Stopped')
		{
			Start-Sleep -Seconds 5
			$ServiceStatus = (Get-Service -Name "connectsvc").Status
		}
		Write-Verbose "Service stopped, restarting"
		Get-Service -Name "connectsvc" | Start-Service
		
		Write-Verbose "Service started, exiting"
		exit
	}
	
	if (-not $SyncConfPath)
	{
		Write-Verbose "Path to sync.conf not specified, trying to extract it from regisrty"
		$AgentInstallPath = (Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\').InstallDir
		$SyncConfPath = Join-Path -Path $AgentInstallPath -ChildPath 'sync.conf'
	}
	
	Write-Verbose "Load sync.conf content, path is $SyncConfPath"
	$syncconf = Get-Content -Path $SyncConfPath | Out-String | ConvertFrom-Json
	
	Write-Verbose "Updating standard parameters if necessary"
	if ($NewBootstrap) { $syncconf.management_server.bootstrap_token = $NewBootstrap }
	if ($DisableCertCheck) { $syncconf.management_server.disable_cert_check = $true }
	if ($EnableCertCheck) { $syncconf.management_server.disable_cert_check = $false }
	if ($NewHost) { $syncconf.management_server.host = $NewHost }
	if ($NewFingerprint) { $syncconf.management_server.cert_authority_fingerprint = $NewFingerprint }
	if ($NewStoragePath) { $syncconf.folders_storage_path = $NewStoragePath }
	
	if ($EnableAgentUI)
	{
		Write-Verbose "Operating agent UI explicitly via parameter"
		$CustomParameterName = "use_gui"
		$CustomParameterValue = "true"
	}
	
	if ($CreateAgentUIShortcut)
	{
		Write-Verbose "Creating agent shortcut for all users"
		Create-AgentShortcut -PathToShortcut ([Environment]::GetFolderPath("CommonDesktopDirectory"))
	}
	
	if ($AutorunAgentUI)
	{
		Write-Verbose "Creating agent shortcut in autoruns section for all users"
		Create-AgentShortcut -PathToShortcut ([Environment]::GetFolderPath("CommonStartup"))
	}
	
	if ($CustomParameterName)
	{
		Write-Verbose "Changing custom parameter $CustomParameterName"
		if ($RemoveCustomParameter)
		{
			Write-Verbose "Removing custom parameter $CustomParameterName"
			if ($CustomParameterName -in $syncconf.PSobject.Properties.Name)
			{
				$syncconf.PSObject.Properties.Remove($CustomParameterName)
			}
			else { throw "Parameter `"$CustomParameterName`" not found and therefore not removed" }
		}
		else
		{
			Write-Verbose "Changing custom parameter $CustomParameterName to value $CustomParameterValue"
			# Update custom parameters here, keeping in mind it's type to avoid extra quotes
			$CustomParameterValueTyped = $CustomParameterValue
			if ($CustomParameterValue -as [int]) { [int]$CustomParameterValueTyped = $CustomParameterValue }
			if ($CustomParameterValue -like "*true") { [bool]$CustomParameterValueTyped = $true }
			if ($CustomParameterValue -like "*false") { [bool]$CustomParameterValueTyped = $false }
			Add-Member -InputObject $syncconf -NotePropertyName $CustomParameterName -NotePropertyValue $CustomParameterValueTyped -Force
		}
	}
	
	Set-Content -Path $SyncConfPath -Value (ConvertTo-Json $syncconf)
	Write-Output "sync.conf file updated"
	
	if ($RestartAgent)
	{
		Write-Verbose "Scheduling agent graceful restart"
		$SchedulerXML = "$xmlpart1$ownscriptpathname$xmlpart2"
		Set-Content -Path "ResilioRestart.xml" -Value $SchedulerXML
		Start-Process -FilePath "schtasks" -ArgumentList "/create /TN ResilioRestart /XML ResilioRestart.xml /F"
		Start-Sleep -Seconds 3
		Start-Process -FilePath "schtasks" -ArgumentList "/run /tn ResilioRestart"
		Write-Output "Attempting agent restart"
	}
}
catch
{
	Write-Verbose "Exception triggered"
	Write-Error "$_"
	Write-Output "sync.conf not modified"
}

Write-Verbose "Script done"