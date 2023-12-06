[CmdletBinding()]
param
(
	[int]$AgentCount = -1,
	[switch]$DontStartService
)

<#
.SYNOPSIS
The script is intended to spin up additional agents on current system or remove them if you no longer need them

.DESCRIPTION
The script creates extra syncX.conf files in primary agent installation folder, extra strorage folders in
either, extra services and starts them. Script must be started under administrator accound (elevated privileges).
The storage paths would be either %ProgramData%\Resilio\Connect Agent X or whatever path specified in sync.conf parameter storage_path
When removing extra agents - script will clean up storage folder and syncX.conf file. That may fail if service does not stop gracefully

.PARAMETER AgentCount
Set the desired agent count. If actual amount is lesser - the script will spin up additional ones. If actual amount is greater - the script 
will remove extras.
If set to -1 will just show the existing amount of agents.
The AgentCount can't be lesser than agents installed via MSI. For example, if you get MC installed via MSI and Agent installed via MSI -
the script won't be able to reduce amount of agents below 2.

.PARAMETER DontStartService
Set the parameter to prevent agent starting up extra agent services after creation

.LINK
https://github.com/resilio-inc/connect-scripts/tree/master/Multiple%20Agents
#>

$ActualAgentCount = 0
$NonRemovableAgentCount = 0

$tmp = Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio Inc.\Resilio Connect Console\' -ErrorAction SilentlyContinue
if ($tmp)
{
	$AgentExecutable = "$($tmp.InstallDir)\agent\Resilio Connect Agent.exe"
	$ConfigPath = "$($env:ProgramData)\Resilio\Connect Server\sync.conf"
	$NonRemovableAgentCount++
	$ActualAgentCount++
}

$tmp = Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\' -ErrorAction SilentlyContinue
if ($tmp)
{
	$AgentExecutable = "$($tmp.InstallDir)\Resilio Connect Agent.exe"
	$ConfigPath = "$($tmp.InstallDir)\sync.conf"
	$NonRemovableAgentCount++
}

$services = Get-Service -Name "connectsvc*"
$ActualAgentCount += $services.Length

if ($AgentCount -eq -1)
{
	Write-Host "Total agents runnung on system: $ActualAgentCount"
	exit 0
}

# Verify if PS is 5 or newer
if ($PSVersionTable.PSVersion -lt "5.1")
{
	throw "Powershell must be 5.1 or newer"
}

# Verify if config exists at all
if (![System.IO.File]::Exists($ConfigPath))
{
	throw "Config file not found: `"$ConfigPath`""
}

# Verify if we are running with eleveate privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
	throw "Script is not running with elevated privileges, impossible to add / remove agents"
}

# Spin up additional agents here
if ($AgentCount -gt $ActualAgentCount)
{
	$AgentsToCreate = $AgentCount - $ActualAgentCount
	$AgentIndex = $ActualAgentCount + 1
	Write-Host "Creating additional $AgentsToCreate agent service(s)"
	for ($i = $AgentIndex; $i -lt ($AgentIndex + $AgentsToCreate); $i++)
	{
		Write-Host "Creating new sync.conf config file... " -NoNewline
		$syncconf = Get-Content $ConfigPath | ConvertFrom-Json
		if ($syncconf.use_gui) { $syncconf.use_gui = $false }
		if ($syncconf.device_name) { $BaseName = $syncconf.device_name }
		else { $BaseName = hostname }
		if ($syncconf.storage_path) { $BaseStoragePath = "$(Split-Path $syncconf.storage_path)\Connect Agent" }
		else { $BaseStoragePath = "$($env:ProgramData)\Resilio\Connect Agent" }
		if ($syncconf.cmd_pipe_name) { $syncconf.psobject.properties.remove("cmd_pipe_name")}
		if ($syncconf.mgmt_server_peer) { $syncconf.psobject.properties.remove("mgmt_server_peer") }
		
		$syncconf | Add-Member -NotePropertyName "device_name" -NotePropertyValue "$BaseName-$i" -Force
		$syncconf | Add-Member -NotePropertyName "storage_path" -NotePropertyValue "$BaseStoragePath $i" -Force
		
		$NewConfigPath = "$(Split-Path $ConfigPath)\sync$i.conf"
		$syncconf | ConvertTo-Json -Depth 10 | Set-Content $NewConfigPath
		Write-Host "Done!"
		
		Write-Host "Creating new storage folder... " -NoNewline
		New-Item -Path "$BaseStoragePath $i" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
		Write-Host "Done!"
		
		Write-Host "Registering new service connectsvc$i... " -NoNewline
		& $AgentExecutable /svcinstall -n "connectsvc$i" -a -u `"LOCAL SYSTEM`" `"`" -t -c `"\`"/config\`" \`"$NewConfigPath\`"`"
		Start-Sleep -Seconds 3
		if ((Get-Service -Name "connectsvc$i").Length -gt 0) { Write-Host "Done!" }
		else {Write-Host "Error! New service not found"}
		
		if (!$DontStartService)
		{
			Write-Host "Starting service connectsvc$i... " -NoNewline
			Start-Service -Name "connectsvc$i"
			Start-Sleep -Seconds 3
			if ((Get-Service -Name "connectsvc$i").Status -eq "Running") { Write-Host "Done!" }
		}
	}
	Write-Host "Additional services created. Exiting script"
	exit 0
}

# Remove extra agents here
if ($AgentCount -lt $ActualAgentCount)
{
	$AgentsToRemove = $ActualAgentCount - $AgentCount
	Write-Host "Removing redundant $AgentsToRemove agent service(s)"
	if ($AgentCount -lt $NonRemovableAgentCount)
	{
		Write-Host "Cannot remove agents below $NonRemovableAgentCount. Script exiting"
		exit 1
	}
	for ($i = $ActualAgentCount; $i -gt $AgentCount; $i--)
	{
		$syncconf = Get-Content $ConfigPath | ConvertFrom-Json
		if ($syncconf.storage_path) { $BaseStoragePath = "$(Split-Path $syncconf.storage_path)\Connect Agent" }
		else { $BaseStoragePath = "$($env:ProgramData)\Resilio\Connect Agent" }
		$NewConfigPath = "$(Split-Path $ConfigPath)\sync$i.conf"
		
		Write-Host "Stopping agent service connectsvc$i... " -NoNewline
		Stop-Service -Name "connectsvc$i" -Force
		Start-Sleep -Seconds 5
		$srv = Get-Service -Name "connectsvc$i"
		if ($srv.Status -ne 'Stopped') { Write-Host "Failed!" }
		else { Write-Host "Done!" }
		
		Write-Host "Deleting agent service connectsvc$i... " -NoNewline
		sc.exe delete "connectsvc$i"
		
		Write-Host "Deleting relevant config file #$i... " -NoNewline
		Remove-Item -Path $NewConfigPath -Force
		Write-Host "Done!"
		
		Write-Host "Deleting relevant storage folder `"$BaseStoragePath $i`"..." -NoNewline
		Remove-Item -Path "$BaseStoragePath $i" -Force -Recurse
		Write-Host "Done!"
	}
	Write-Host "Redundant services removed. Exiting script"
	exit 0
}

if ($AgentCount -eq $ActualAgentCount)
{
	Write-Host "$ActualAgentCount agents run this system. No need to add / remove. Exiting script."
	exit 0
}