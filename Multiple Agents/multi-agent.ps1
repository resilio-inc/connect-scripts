[CmdletBinding()]
param
(
	[int]$AgentCount = 0,
	[switch]$DontStartService
)

$ActualAgentCount = 0

$tmp = Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio Inc.\Resilio Connect Console\' -ErrorAction SilentlyContinue
if ($tmp)
{
	$MCInstalled = $true
	$AgentExecutable = "$($tmp.InstallDir)\agent\Resilio Connect Agent.exe"
	$ConfigPath = "$($env:ProgramData)\Resilio\Connect Server\var\sync.conf"
}
else { $MCInstalled = $false }

$tmp = Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\' -ErrorAction SilentlyContinue
if ($tmp)
{
	$AgentInstalled = $true
	$ActualAgentCount++
	$AgentExecutable = "$($tmp.InstallDir)\Resilio Connect Agent.exe"
	$ConfigPath = "$($tmp.InstallDir)\sync.conf"
}
else { $AgentInstalled = $false }

if (![System.IO.File]::Exists($ConfigPath))
{
	throw "Config file not found: `"$ConfigPath`""
}

if ($AgentCount -eq 0)
{
	$services = Get-Service -Name "connectsvc*"
	$ActualAgentCount += $services.Length
	Write-Host "Total agents runnung on system: $ActualAgentCount"
	exit 0
}

# Spin up additional agents here
if ($AgentCount -gt $ActualAgentCount)
{
	$AgentsToCreate = $AgentCount - $ActualAgentCount
	$AgentIndex = $AgentCount + 1
	for ($i = $AgentIndex; $i -lt ($AgentIndex + $AgentsToCreate); $i++)
	{
		$syncconf = Get-Content $ConfigPath | ConvertFrom-Json
		if ($syncconf.use_gui) { $syncconf.use_gui = $false }
		if ($syncconf.device_name) { $BaseName = $syncconf.device_name }
		else { $BaseName = hostname }
		if ($syncconf.storage_path) { $BaseStoragePath = "$(Split-Path $syncconf.storage_path)\Connect Agent" }
		else { $BaseStoragePath = "$($env:ProgramData)\Resilio\Connect Agent" }
		$syncconf | Add-Member -NotePropertyName "device_name" -NotePropertyValue "$BaseName-$i" -Force
		$syncconf | Add-Member -NotePropertyName "storage_path" -NotePropertyValue "$BaseStoragePath $i" -Force
		
		
		$NewConfigPath = "$(Split-Path $ConfigPath)\sync$i.conf"
		$syncconf | ConvertTo-Json -Depth 10 | Set-Content $NewConfigPath
		
		if (!$DontStartService) { Start-Service -Name "connectsvc$i" }
	}
}

# Remove extra agents here
if ($AgentCount -lt $ActualAgentCount)
{
	
}