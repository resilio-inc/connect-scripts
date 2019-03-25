[CmdletBinding()]
Param ()

<#
.SYNOPSIS
The script is intended to upgrade current installation of Resilio Connect Agent to required version.

.DESCRIPTION
If done via Connect Job, upgrade script should advised to be started by TaskScheduler service to 
completely detach from launching agent. It's recommended to start script from "C:\ResilioUpgrade" 
folder. Script expects next files to be present in the script folder: 
  oldstorage.path" - should contain path to current storage folder. Used when migrating 2.4 agent
                     to 2.5 agent
  Resilio-Connect-Agent.exe - x86 version of executable. Used to replace original one
  Resilio-Connect-Agent_x64.exe - x64 version of executable

Proper version is selected automatically.

Script stops the service and waits 10 minutes to get service shut down. After that it kills the
service process and proceed with the replacement.

Script compares the version of existing binary and a new one. If there's a 2.5 version crossed,
script will take care to transfer old storage folder to it's new position 
("C:\ProgramData\Resilio\Connect Agent"). If file "oldstorage.path" not specified, old storage 
is taken from 
"C:\Windows\System32\config\systemprofile\AppData\Roaming\Resilio Connect Agent Service\"

.OUTPUTS
Script drops the upgrade.log to the folder it started from
#>

# Define own paths and names
$ownscriptpathname = (Resolve-Path $MyInvocation.InvocationName).Path
$ownscriptpath = Split-Path -Path $ownscriptpathname
$ownscriptname = Split-Path $ownscriptpathname -Leaf

# Start logging
Start-Transcript -Path "$ownscriptpath\upgrade.log" -Append

Write-Verbose "Upgrade script started"
try
{
	# Define common names and paths used below
	if ([System.IO.File]::Exists("$ownscriptpath\oldstorage.path")) { $oldstoragepath = Get-Content "$ownscriptpath\oldstorage.path" }
	else { $oldstoragepath = "$env:SystemRoot\System32\config\systemprofile\AppData\Roaming\Resilio Connect Agent Service\" }
	
	$servicename = "connectsvc"
	$processname = "Resilio Connect Agent.exe"
	$agentupgradeablex86 = "Resilio-Connect-Agent.exe"
	$agentupgradeablex64 = "Resilio-Connect-Agent_x64.exe"
	$newstoragepath = "$env:ProgramData\Resilio\Connect Agent\"
	if ([IntPtr]::size -eq 8)
	{
		$agentupgradeble = $agentupgradeablex64
		Write-Verbose "OS identified as x64 bit version of Windows"
	}
	else
	{
		$agentupgradeble = $agentupgradeablex86
		Write-Verbose "OS identified as x86 bit version of Windows"
	}
	
	$processpath = (Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\').InstallDir
	Write-Verbose "Found Agent installed to: $processpath"
	$fullexepath = Join-Path -Path $processpath -ChildPath $processname
	$fullupgradeablepath = Join-Path -Path $ownscriptpath -ChildPath $agentupgradeble
	[System.Version]$oldversion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$fullexepath").FileVersion
	[System.Version]$newversion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$fullupgradeablepath").FileVersion
	
	Write-Verbose "Currently installed verison of agent is: $oldversion"
	Write-Verbose "Going to upgrade to agent verison: $newversion"
	
	# Stop Agent service
	Write-Verbose "Stopping agent service..."
	Stop-Service -Name $servicename
	
	# Give it some minutes to end in case it got really large DB
	$timer = [system.diagnostics.stopwatch]::StartNew()
	while ($timer.Elapsed.Minutes -lt 10)
	{
		$srv = Get-Service -Name $servicename
		if ($srv.Status -eq 'Stopped')
		{
			Write-Verbose "Agent service stopped gracefully"
			break
		}
		Start-Sleep 1
	}
	$timer.Stop
	
	# If it hangs, kill the process forcefully
	if ($timer.Elapsed.Minutes -ge 10)
	{
		Stop-Process -Name $processname -Force
		Write-Verbose "Agent service failed to stop, killing process"
	}
	
	# Rename old executable
	Move-Item -Path "$fullexepath" -Destination "$fullexepath.old" -Force
	Write-Verbose "Old binary got renamed"
	
	# Put new executable in place of old one
	Copy-Item -Path $fullupgradeablepath -Destination $fullexepath -Force
	Write-Verbose "New binary is in place"
	
	# Migrate storage from old position to a new one if necessary
	if ($oldversion -lt [System.Version]"2.5.0.0" -and $newversion -ge [System.Version]"2.5.0.0")
	{
		Write-Verbose "Migrating old storage to a new position in ProgramData"
		# Ensure folder exists
		if (!(Test-Path $newstoragepath)) { New-Item -Path "$newstoragepath" -ItemType Directory -Force | Out-Null }
		
		# Set full perms to local system user
		# Disable ACLs temporary
		#$perms = Get-Acl "$newstoragepath"
		#$newperms = New-Object System.Security.AccessControl.FileSystemAccessRule("LOCAL SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
		#$perms.SetAccessRule($newperms)
		#Set-Acl "$newstoragepath" $perms
		
		Copy-Item -path "$oldstoragepath\*" -Destination "$newstoragepath" -Recurse -Force
	}
	
}
catch
{
	Write-Error "Unexpected error occuerd: $_"
}
finally
{
	# Start Agent service
	Start-Service -Name $servicename
	Write-Verbose "Agent service started"
	
	# Stop logging
	Write-Verbose "Finishing logging"
	Stop-Transcript
}
