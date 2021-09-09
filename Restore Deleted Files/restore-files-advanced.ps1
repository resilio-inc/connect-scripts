[CmdletBinding()]
param
(
	[string]$Path,
	[string]$Database,
	[switch]$WhatIf,
	[String]$Log,
	[datetime]$From,
	[datetime]$To
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

.PARAMETER Log
Specify the path and a filename for the log file to dump information about files restored

.LINK
https://github.com/resilio-inc/connect-scripts/tree/master/Restore%20Deleted%20Files
#>


#---------------------------------------------------------------------------------------------------------------------------------------

function ConvertFrom-UnixTime
{
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[long]$unxtime,
		[switch]$MilliSec,
		[switch]$ConvertToLocal
	)
	if ($MilliSec) { $unxtime = $unxtime/1000 }
	$res = (Get-Date 01.01.1970) + ([System.TimeSpan]::fromseconds($unxtime))
	if ($ConvertToLocal) { $res = $res.ToLocalTime() }
	return $res
}
# --------------------------------------------------------------------------------------------------------------------------------

function Get-BenNumber
{
	$i = 0
	while ($global:bendata[$global:Offset + $i] -match '[-0-9]') # Reading length OR integer here
	{
		$i++
	}
	$number = [long]$global:bendata.Substring($global:Offset, $i)
	$global:Offset += $i + 1 # Skipping the number + trailing 'e'
	return $number
}
# --------------------------------------------------------------------------------------------------------------------------------

function Get-BenValue
{
	param
	(
		[switch]$ValidateHex
	)
	
	if ($global:bendata[$global:Offset] -eq 'i') # Integer object
	{
		$global:Offset++ # Skipping integer type
		$IntNumber = Get-BenNumber
		return $IntNumber
	}
	
	if ($global:bendata[$global:Offset] -eq 'l') # Array object
	{
		$global:Offset++ # Skipping array type
		$res = @()
		while ($global:bendata[$global:Offset] -ne 'e')
		{
			$tmp = Get-BenValue
			$res += $tmp
		}
		$global:Offset++ # Skipping 'e' end marker
		return $res
	}
	
	if ($global:bendata[$global:Offset] -eq 'd') # Dictionary object
	{
		$global:Offset++ # Skipping dictionary type
		$tmp = New-Object System.Object
		while ($global:bendata[$global:Offset] -ne 'e')
		{
			
			$Name = Get-BenValue
			$Value = Get-BenValue -ValidateHex
			$tmp | Add-Member -Type NoteProperty -Name $Name -Value $Value
		}
		$global:Offset++ # Skipping 'e' end marker
		return $tmp
	}
	
	# Any other object goes here
	$len = Get-BenNumber
	
	$Value = $global:bendata.Substring($global:Offset, $len)
	$global:Offset += $len
	
	if ($ValidateHex)
	{
		$ConversionRequired = $false
		foreach ($symbol in [char[]]$Value)
		{
			if ($symbol -lt 0x20)
			{
				$ConversionRequired = $true
				break
			}
		}
		if ($ConversionRequired)
		{
			$bytes = [System.Text.Encoding]::Unicode.GetBytes($Value)
			$Hex = -join ($bytes | % { "{0:X2}" -f $_ })
			$Value = "0x$Hex"
		}
	}
	return $Value
}
# --------------------------------------------------------------------------------------------------------------------------------

Function ConvertFrom-Bencode
{
	param
	(
		[Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'FromFile')]
		$Path,
		[parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'FromPipe')]
		$BencodedData
	)
	if ($Path) { $BencodedData = Get-Content $Path -Raw }
	else { $global:bendata = [System.Text.Encoding]::GetEncoding("Windows-1251").GetString($BencodedData)}
	$global:Offset = 0
	$res = Get-BenValue
	return $res
}
# --------------------------------------------------------------------------------------------------------------------------------

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

Write-Host "Script to restore files from archive v2.1 started"
$ownscriptpathname = $MyInvocation.MyCommand.Definition
$ownscriptpath = Split-Path -Path $ownscriptpathname
$ownscriptname = Split-Path $ownscriptpathname -Leaf

if (!([System.IO.Path]::IsPathRooted($Path)))
{
	Write-Error "Synced folder path can't be relative"
	return
}

$tmp = Import-Module PSSqlite -ErrorAction SilentlyContinue -PassThru
if (!$tmp)
{
	Write-Error "SQLite module `"PSSQlite`" not found and it is mandatory to run the script. Use command `"Install-Module PSSQLite`" to install it in Powershell window with elevated privileges"
	return
}

$tmp = Invoke-SqliteQuery -DataSource "$Database" -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='deleted_files2'"
if (!$tmp)
{
	Write-Error "The agent DB is too old and does not support advanced archived files restoring"
	return
}

$uniques = @{ }
$archive_path = join-path -Path $Path -ChildPath "\.sync\Archive"

if ([String]::IsNullOrEmpty($Log))
{
	$Log = "$ownscriptpath\restore-$(Split-Path $Path -Leaf).log"
}
$LoggerStream = New-Object System.IO.StreamWriter($Log)
$LoggerStream.Write("Script started on $(Get-Date)`n")
$tmp = Invoke-SqliteQuery -DataSource "$Database" -Query "SELECT COUNT(*) FROM deleted_files2"
$TotalEntries = $tmp.'COUNT(*)'

try
{
	Write-Host "Extracting $TotalEntries entries from database"
	$tmp = Invoke-SqliteQuery -DataSource "$Database" -Query "SELECT * FROM deleted_files2"
	
	$EntryIndex = -1
	$OldEntryIndex = -1
	Write-Progress -Activity "Checking removed files" -PercentComplete 0
	foreach ($record in $tmp)
	{
		$EntryIndex++
		if (($EntryIndex - $OldEntryIndex) -gt 10000)
		{
			Write-Progress -Activity "Checking removed files" -Status "Processed $EntryIndex of $TotalEntries" -PercentComplete (($EntryIndex*100) / $TotalEntries)
			$OldEntryIndex = $EntryIndex
		}
		
		
		$unique_file_name = [System.Text.Encoding]::ASCII.GetString($record.original_path)
		$real_position_file_path = "$Path\$unique_file_name"
		$archived_file_path = "$archive_path\$([System.Text.Encoding]::ASCII.GetString($record.path))"
		$tmp_object = ConvertFrom-Bencode -BencodedData $record.data
		$archivation_time = ConvertFrom-UnixTime $tmp_object.mtime -ConvertToLocal
		if (Test-Path -LiteralPath $real_position_file_path -PathType Leaf)
		{
			# File exists outside of the archive, so it's just a version of non removed file
			continue
		}
		if (!(Test-Path -LiteralPath $archived_file_path -PathType Leaf))
		{
			# File in achive deos not exist, likely human interventon
			$LoggerStream.Write("Missing file in archive: `"$archived_file_path`"`n")
			continue
		}
		
		UpdateUniqueList -unique_filename $unique_file_name -modification_time $archivation_time -archived_filename $archived_file_path
	}
	Write-Progress -Activity "Checking removed files" -Status "Processed $EntryIndex of $TotalEntries" -Completed
	
	$EntryIndex = -1
	$OldEntryIndex = -1
	$TotalEntries = $uniques.Count
	Write-Host "Total files deleted: $TotalEntries, restoring"
	Write-Progress -Activity "Restoring files" -PercentComplete 0
	foreach ($key in $uniques.Keys)
	{
		$EntryIndex++
		if (($EntryIndex - $OldEntryIndex) -gt 1000) # Display progress for each 1K entries to not to consume too much performance
		{
			Write-Progress -Activity "Restoring files" -Status "Restored $EntryIndex of $TotalEntries total" -PercentComplete (($EntryIndex * 100) / $TotalEntries)
			$OldEntryIndex = $EntryIndex
		}
		$fileprops = $uniques[$key]
		$mtime = $fileprops['mtime']
		$fullarchivedpath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($fileprops['archived_name'])
		$tmp = "$Path\$key"
		$real_position_path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($tmp)
		if ($From)
		{
			if ($mtime -lt $From)
			{
				$LoggerStream.Write("Ignoring (time) `"$fullarchivedpath`" archived on $mtime`n")
				continue
			}
		}
		if ($To)
		{
			if ($mtime -gt $To)
			{
				$LoggerStream.Write("Ignoring (time) `"$fullarchivedpath`" archived on $mtime`n")
				continue
			}
		}
		
		if ($WhatIf)
		{
			$msg = "File `"$real_position_path`" has been deleted. Can be restored from `"$fullarchivedpath`" archived on $mtime"
			$LoggerStream.Write("$msg`n")
			Write-Host $msg
		}
		else
		{
			$msg = "Restoring `"$fullarchivedpath`" to `"$real_position_path`" archived on $mtime"
			$LoggerStream.Write("$msg`n")
			Write-Host $msg
			EnsurePathExist($real_position_path)
			Move-Item -LiteralPath $fullarchivedpath -Destination $real_position_path
		}
	}
	Write-Progress -Activity "Restoring files" -Status "Restored $EntryIndex of $TotalEntries total" -Completed
	
}
catch
{
	$LoggerStream.Write("$_`n")
	Write-Error $_
}
finally
{
	$LoggerStream.Close()
	Remove-Module PSSQLite
}
