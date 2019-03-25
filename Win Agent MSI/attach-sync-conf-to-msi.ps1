<#
.SYNOPSIS 
This script is intended to embed your sync.conf file into MSI installer, 
generating effective ready-to-consume installer file.

.DESCRIPTION
By default, MSI installer requires sync.conf configuration file to stay 
next to installer (or be specified manually during installation) to allow 
connection to Management Console server. Keeping it in 2 separate files
sometimes not acceptable by administrators. This script allows to embed
sync.conf file as a part of MSI installer. Resulting single-file MSI 
installer will install Connect Agent and automatically connect it to 
Management console.
Embedding sync.conf breaks Resilio, Inc. digital signature of the MSI
installer. Therefore, you'll need to re-sign it with your own certificate
if necessary.

.PARAMETER MSIPath
Full path to the MSI installer file to embed sync.conf into

.PARAMETER SyncConfPath
Full path to sync.conf file produced by Management Console. Technically, 
the file can bear different name.

.EXAMPLE
attach-sync-conf-to-msi.ps1 -MSIPath "C:\Downloads\Resilio-Connect-Agent_x64.msi" -SyncConfPath "C:\Downloads\sync.conf"

Operation complete. Configuration file inserted into "c:\Downloads\Resilio-Connect-Agent_x64.msi" MSI installer. Result saved in "Resilio-Connect-Agent_x64_configured.msi"
MSI file signature is broken. Please re-sign if necessary.
#>

param (
	[parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	$MSIPath,
	[parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	$SyncConfPath
)

# Define own paths and names
$ownscriptpathname = (Resolve-Path $MyInvocation.InvocationName).Path
$ownscriptpath = Split-Path -Path $ownscriptpathname
$ownscriptname = Split-Path $ownscriptpathname -Leaf

try
{
	# Load and BASE64-encode sync.conf
	$SyncConf = Get-Content -Path $SyncConfPath -Encoding Byte
	$SyncConfEncoded = [Convert]::ToBase64String($SyncConf)
	
	# Open the MSI database
	$WindowsInstallerCOM = New-Object -ComObject WindowsInstaller.Installer
	$MSIDatabase = $WindowsInstallerCOM.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstallerCOM, @($MSIPath, 2))
	
	# Try to insert config as "CONFIG_BASE64" property in "Property" table of MSI DB
	$Query = "INSERT INTO `Property` (`Property`.`Property`, `Property`.`Value`) VALUES ('CONFIG_BASE64', '$SyncConfEncoded')"
	$View = $MSIDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $MSIDatabase, ($Query))
	$View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
	
	$MSIDatabase.GetType().InvokeMember("Commit", "InvokeMethod", $null, $MSIDatabase, $null)
	$View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)
	
	$MSIPathOnly = Split-Path -Path $MSIPath
	$MSINameOnly = [System.IO.Path]::GetFileNameWithoutExtension($MSIPath)
	$MSINewName = Join-Path -Path $MSIPathOnly -ChildPath "$($MSINameOnly)_configured.msi"
	
	# Free COM objects to release MSI file
	$MSIDatabase = $null
	$View = $null
	[System.GC]::Collect()
	
	Start-Sleep 1
	
	# Rename file to indicate it has config embedded
	Move-Item -Path $MSIPath -Destination $MSINewName
	
	# Report success to user
	Write-Output "Operation complete. Configuration file inserted into `"$MSIPath`" MSI installer. Result saved in `"$($MSINameOnly)_configured.msi`""
	Write-Output "MSI file signature is broken. Please re-sign if necessary."
}
catch {
	# Free COM objects in case of exception
	$MSIDatabase = $null
	$View = $null
	Write-Error -Message $_.Exception.Message
}

