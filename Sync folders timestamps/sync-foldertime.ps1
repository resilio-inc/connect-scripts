<#
.SYNOPSIS
This script is intended to copy folders modification time and creation time after delivery with Resilio Connect.

.DESCRIPTION
Use the script after data delivery with Resilio Connect product. Resilio Connect does not syncrhonize folders modification and folder creation time. This script can do it.
Run the script twice: first time to collect a snapshot of folders tree on the source into a file and a second time to apply collected folder timestamps on destination machine.
The script does not synchronize folder access time (and not intended to).

.PARAMETER MakeSnapshot 
Specify if you want script to collect folders tree with timestamps.

.PARAMETER ApplyFolderTimes
Specify if you watn script to apply folder timestamps from a snapshot to live directory

.PARAMETER OutFile
Specify the path and a filename to save folders snapshot with timestamps. Recommended to use .xml extension

.PARAMETER PathToSnapshot
Specify the path and a filename of existing snapshot of folders with timestamps.

.PARAMETER DestinationPath
Specify the path to a live folder where you want apply timestamps from snapshot

.PARAMETER SourcePath
When creating snapshot: specify the path of a source folder
When applying snapshot: specify to give a script reference point of a root folder in the snapshot. If not specified, the script will calculate root folder automatically.

.EXAMPLE
.\sync-foldertime.ps -MakeSnapshot -SourcePath 'C:\Mysourcefolder' -OutFile mysnapshot.xml
Creates a snapshot of all folder timestamps in C:\Mysourcefolder and saves it to mysnapshot.xml

.EXAMPLE
 .\sync-foldertime.ps1 -ApplyFolderTimes -PathToSnapshot 'C:\mysnapshot.xml' -DestinationPath 'C:\MydestinationFolder'
Grabs the snapshot from first example and applies it to the directory C:\MydestinationFolder. The example assumes it was synchronized already with Resilio Connect
#>

param
(
	[parameter(ParameterSetName = "Snapshot", Position = 1)]
	[switch]$MakeSnapshot,
	[parameter(ParameterSetName = "Apply", Position = 1)]
	[switch]$ApplyFolderTimes,
	[parameter(ParameterSetName = "Snapshot", Mandatory = $true)]
	[string]$OutFile,
	[parameter(ParameterSetName = "Apply", Mandatory = $true)]
	[string]$PathToSnapshot,
	[parameter(ParameterSetName = "Apply", Mandatory = $true)]
	[string]$DestinationPath,
	[parameter(ParameterSetName = "Apply")]
	[parameter(ParameterSetName = "Snapshot", Mandatory = $true)]
	[string]$SourcePath
)


# ----------------------------------------------------------------------------------------------------------------------------------------------------

if ($MakeSnapshot)
{
	Write-Host "Making directory tree snapshot, please be patient..."
	$allfolders = Get-ChildItem -Path $SourcePath -Recurse -Attributes Directory
	$allfolders | Export-Clixml $OutFile
	Write-Host "Total folders captured: $($allfolders.Count)"
}

if ($ApplyFolderTimes)
{
	$failed_attempts = 0
	Write-Host "Loading folders tree..."
	$allfolders = Import-Clixml -Path $PathToSnapshot
	if (!$SourcePath) { $SourcePath = $allfolders[0].Parent.FullName }
	$SourcePath = $SourcePath.TrimEnd('\')
	$SourceDepth = $SourcePath.Split('\').Count
	$RelativePathRegEx = '.:\\' + '[^\\]*\\' * ($SourceDepth - 1) + '(.*)'
	
	Write-Host "Calculating tree depth..."
	foreach ($folder in $allfolders)
	{
		$tmp = $folder.FullName.Split('\').Count
		$folder | Add-Member -NotePropertyName "PathDepth" -NotePropertyValue $tmp
	}
	
	Write-Host "Sorting folders tree by depth..."
	$allfolders = $allfolders | Sort-Object -Property PathDepth -Descending
	
	Write-Host "Setting each folder mtime and ctime..."
	foreach ($folder in $allfolders)
	{
		if (!($folder.FullName -match $RelativePathRegEx)) { throw "Can`'t split path `"$($folder.FullName)`" with regex `"$RelativePathRegEx`"" }
		$NewPath = Join-Path -Path $DestinationPath -ChildPath $Matches[1]
		if (!(Test-Path $NewPath)) { Write-Host "Can`'t set time for `"$NewPath`" as it does not exist"; $failed_attempts++ }
		else
		{
			(Get-Item $NewPath).LastWriteTime = $folder.LastWriteTime
			(Get-Item $NewPath).CreationTime = $folder.CreationTime
		}
	}
	Write-Host "Total folders $($allfolders.Count), failed to apply $failed_attempts"
}
Write-Host "Script done"
