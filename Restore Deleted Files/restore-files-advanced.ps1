[CmdletBinding()]
param
(
	[string]$Path,
	[string]$Database,
	[switch]$WhatIf
)

<#
.SYNOPSIS
The script is intended to restore files from the archive. It requires agent v2.12 as it extracts removed records information from database.
Ensure that the agent is not running when using the script.

.DESCRIPTION
The script crawls over the "deleted_files2" table from the database corresponding to a job. It only picks records for the files that
do not exist in synced folder and restores the latest version.

.PARAMETER Path
Path to the synced folder root. Must be absolute

.PARAMETER Database
Path to the database file (<hash>.db). Check the hash value of the DB in Dump debug status of Management Console. Note it is not the
<hash>.files.db or <hash>.sf.db

.PARAMETER WhatIf
Set the parameter to only display the files to be restored

.LINK
https://github.com/resilio-inc/connect-scripts/tree/master/Restore%20Deleted%20Files
#>

#---------------------------------------------------------------------------------------------------------------------------------------

function EnsurePathExist($path)
{
	$path_only = Split-Path -Path $path
	
	if (!(Test-Path $path_only))
	{
		New-Item -Path $path_only -ItemType Directory -Force | Out-Null
	}
}
#---------------------------------------------------------------------------------------------------------------------------------------

function UpdateUniqueList($unique_filename, $modification_time, $archived_filename)
{
	$uniquefileprops = @{
		'mtime'		    = $modification_time
		'archived_name' = $archived_filename
		'status'	    = "unknown"
	}
	
	if ([string]::IsNullOrEmpty($unique_filename))
	{
		return
	}
	
	if ($uniques.ContainsKey($unique_filename))
	{
		$timediff = New-TimeSpan $uniques[$unique_filename]['mtime'] $modification_time
		if ($timediff -gt 0)
		{
			$uniques[$unique_filename] = $uniquefileprops
		}
	}
	else
	{
		$uniques.Add($unique_filename, $uniquefileprops)
	}
	
}
#---------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------------------------------

Write-Host "Script to restore files from archive v2.0 started"
if (!([System.IO.Path]::IsPathRooted($Path)))
{
	Write-Error "Synced folder path can't be relative"
	return
}

$uniques = @{ }
$archive_path = join-path -Path $Path -ChildPath "\.sync\Archive"

Import-Module PSSqlite

try
{
	$tmp = Invoke-SqliteQuery -DataSource "$Database" -Query "SELECT * FROM deleted_files2"
	
	foreach ($record in $tmp)
	{
		$unique_file_name = [System.Text.Encoding]::ASCII.GetString($record.original_path)
		$real_position_file_path = "$Path\$unique_file_name"
		$archived_file_path = "$archive_path\$([System.Text.Encoding]::ASCII.GetString($record.path))"
		if (Test-Path -LiteralPath $real_position_file_path -PathType Leaf) 
		{   # File exists outside of the archive, so it's just a version of non removed file
			continue
		}
		if (!(Test-Path -LiteralPath $archived_file_path -PathType Leaf))
		{   # File in achive deos not exist, likely human interventon
			Write-Verbose "Manually restored: `"$archived_file_path`""
			continue
		}
		
		$tmp_file_in_archive = Get-Item -Path $archived_file_path
		UpdateUniqueList -unique_filename $unique_file_name -modification_time $tmp_file_in_archive.LastWriteTime -archived_filename $archived_file_path
	}
	
	foreach ($key in $uniques.Keys)
	{
		$fileprops = $uniques[$key]
		$mtime = $fileprops['mtime']
		$fullarchivedpath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($fileprops['archived_name'])
		$tmp = "$Path\$key"
		$real_position_path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($tmp)
		if ($WhatIf)
		{
			Write-Host "File `"$real_position_path`" has been deleted. Can be restored from `"$fullarchivedpath`" archived on $mtime"
		}
		else
		{
			Write-host "Restoring `"$fullarchivedpath`" to `"$real_position_path`" archived on $mtime"
			EnsurePathExist($real_position_path)
			Move-Item -LiteralPath $fullarchivedpath -Destination $real_position_path
		}
	}
	
}
catch
{
	Write-Error "Unable to open DB: $_"
}
finally
{
	Remove-Module PSSQLite
}
