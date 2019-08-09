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

$extractor = @"
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

public class ExtractData
{
    [System.Flags]
    enum LoadLibraryFlags : uint
    {
        None = 0,
        DONT_RESOLVE_DLL_REFERENCES = 0x00000001,
        LOAD_IGNORE_CODE_AUTHZ_LEVEL = 0x00000010,
        LOAD_LIBRARY_AS_DATAFILE = 0x00000002,
        LOAD_LIBRARY_AS_DATAFILE_EXCLUSIVE = 0x00000040,
        LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x00000020,
        LOAD_LIBRARY_SEARCH_APPLICATION_DIR = 0x00000200,
        LOAD_LIBRARY_SEARCH_DEFAULT_DIRS = 0x00001000,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR = 0x00000100,
        LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x00000800,
        LOAD_LIBRARY_SEARCH_USER_DIRS = 0x00000400,
        LOAD_WITH_ALTERED_SEARCH_PATH = 0x00000008
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern IntPtr LoadLibrary([MarshalAs(UnmanagedType.LPStr)]string lpFileName);


    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hReservedNull, LoadLibraryFlags dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32.dll")]
    static extern IntPtr FindResource(IntPtr hModule, IntPtr lpName, IntPtr lpType);


    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

    [DllImport("Kernel32.dll", EntryPoint = "SizeofResource", SetLastError = true)]

    private static extern uint SizeofResource(IntPtr hModule, IntPtr hResource);


    public byte[] ExtractDLLFromEXE(string file, int number)
    {
        IntPtr lib = IntPtr.Zero;
        lib = LoadLibraryEx(file, IntPtr.Zero, LoadLibraryFlags.LOAD_LIBRARY_AS_DATAFILE);

        String type = "BIN";
        IntPtr strPtr = new IntPtr(number);
        IntPtr p = FindResource(lib, strPtr, Marshal.StringToHGlobalAnsi(type));
        int size = (int)SizeofResource(lib, p);

        p = LoadResource(lib, p);

        byte[] dll = new byte[size];
        Marshal.Copy(p, dll, 0, size);

        FreeLibrary(lib);

        return dll;
    }
}
"@

$xmlpart1 = '<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<RegistrationInfo>
<Date>2019-08-08T05:20:27.7653597</Date>
<Author>ResilioInc</Author>
</RegistrationInfo>
<Triggers />
<Principals>
<Principal id="Author">
<UserId>'

$xmlpart2 = '</UserId>
<LogonType>InteractiveToken</LogonType>
<RunLevel>LeastPrivilege</RunLevel>
</Principal>
</Principals>
<Settings>
<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
<DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
<StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
<AllowHardTerminate>true</AllowHardTerminate>
<StartWhenAvailable>false</StartWhenAvailable>
<RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
<IdleSettings>
<StopOnIdleEnd>true</StopOnIdleEnd>
<RestartOnIdle>false</RestartOnIdle>
</IdleSettings>
<AllowStartOnDemand>true</AllowStartOnDemand>
<Enabled>true</Enabled>
<Hidden>false</Hidden>
<RunOnlyIfIdle>false</RunOnlyIfIdle>
<WakeToRun>false</WakeToRun>
<ExecutionTimeLimit>P3D</ExecutionTimeLimit>
<Priority>7</Priority>
</Settings>
<Actions Context="Author">
<Exec>
<Command>explorer.exe</Command>
</Exec>
</Actions>
</Task>'

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
	$extensionx86 = "SyncShellContextMenu_x86.dll"
	$extensionx64 = "SyncShellContextMenu_x64.dll"
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
	$fullextx86path = Join-Path -Path $processpath -ChildPath $extensionx86
	$fullextx64path = Join-Path -Path $processpath -ChildPath $extensionx64
	
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
	
	# Upgrade Explorer extension DLLs if they are installed
	if ([System.IO.File]::Exists("$fullextx86path"))
	{
		# Rename old extension DLLs
		Remove-Item -Path "$fullextx86path.old" -Force -ErrorAction SilentlyContinue
		Remove-Item -Path "$fullextx64path.old" -Force -ErrorAction SilentlyContinue
		Move-Item -Path "$fullextx86path" -Destination "$fullextx86path.old" -Force
		Move-Item -Path "$fullextx64path" -Destination "$fullextx64path.old" -Force
		Write-Verbose "Old extension DLLs were renamed"
		
		# Extract new extension DLLs in place of old ones
		Add-Type -TypeDefinition $extractor		
		$objextrator = New-Object ExtractData
		$dllx86 = $objextrator.ExtractDLLFromEXE($fullexepath, 418)
		$dllx64 = $objextrator.ExtractDLLFromEXE($fullexepath, 419)
		Set-Content -Path $fullextx86path -Value $dllx86 -Encoding Byte
		Set-Content -Path $fullextx64path -Value $dllx64 -Encoding Byte
		Write-Verbose "New extension DLLs are in place"
		
		# Restart explorer so new DLLs take effect
		$currentloggeduser = (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue).UserName
		if ($currentloggeduser)
		{
			Write-Verbose "Found user `"$currentloggeduser`" logged in, attempting to restart explorer.exe"
			Stop-Process -Name explorer -Force
			Start-Sleep 5
			if (!(Get-Process -Name explorer))
			{
				Write-Verbose "Explorer did not restart automatically, restarting via Task Scheduler"
				$ExplorerXML = "$xmlpart1$currentloggeduser$xmlpart2"
				Set-Content -Path "StartExplorer.xml" -Value $ExplorerXML
				Start-Process -FilePath "schtasks" -ArgumentList "/create /TN StartExplorer /XML StartExplorer.xml /F"
				Start-Sleep -Seconds 3
				Start-Process -FilePath "schtasks" -ArgumentList "/run /tn StartExplorer"
			}
			else
			{
				Write-Verbose "Explorer restarted automatically by OS"
			}
		}
		else
		{
			Write-Verbose "No user logged in, explorer restart is not required"
		}
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
