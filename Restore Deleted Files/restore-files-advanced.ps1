<#
.SYNOPSIS
The script is intended to restore files from the archive. It either runs thru the .sync/Archive to restore files that do not exist
outside of the archive or runs thru DB of removed files to restore them.

.DESCRIPTION
The script can run in 2 modes: 
- Basic mode: crawls thru the archive and searching for files that do not exist outside of the archive. This way is old, reliable
  but unable to restore files of a type "your_rendered_image.1334.exr" as it thinks "1334" is a version in archive and will only
  restore one of such files.
- Advanced mode: it gets the information about restored files from agent's database table "deleted_files2". It only picks records 
  for the files that do not exist in synced folder and restores the latest version. Agent attempts to open database in read-only
  mode but it is still not recommended to keep the Agent running when opening its database. Copying database together with db-wal
  file is a viable solution.
The script can pull the list of jobs, their paths and databases from agent's Storage folder. If you are not using default storage
folder location - please specify it with -Storage parameter

.PARAMETER JobName
Specify to pull job path / database from Agent's storage folder. JobName accepts wildcards, so "Full*" will work for "FullSync"

.PARAMETER Storage
Specify to get job properties from Agent with non-default storage location

.PARAMETER Path
Path to the synced folder root. Must be absolute

.PARAMETER Database
Path to the database file (<hash>.db). Check the hash value of the DB in Dump debug status of Management Console. Note it is not the
<hash>.files.db or <hash>.sf.db

.PARAMETER WhatIf
Set the parameter to only display the files to be restored

.PARAMETER Log
Specify the path and a filename for the log file to dump information about files restored

.PARAMETER CSV
Specify the path and a filename for the CSV file to dump list of files with their status there

.PARAMETER From
Specify the date in PS DateTime format. String "YYYY-MM-DD HH:mm:ss" works. Script only restores files moved to the archive AFTER (strictly) that date.

.PARAMETER To
Specify the date in PS DateTime format. String "YYYY-MM-DD HH:mm:ss" works. Script only restores files moved to the archive BEFORE (strictly) that date.

.PARAMETER SupportLongPath
Set the parameter to prevent script from failing on a long paths (longer than 260 symbols). Requires Powershell 5.1 or newer.

.PARAMETER ListJobs
Specify to let script show all jobs that Agent owns. You can use the job name later to get path or database automatically

.EXAMPLE
restore-files-advanced.ps1 -Path 'c:\TestFolders\FullSync' -Log "restore-fullsync-dryrun.log" -CSV "list-of-files.csv" -WhatIf
Lists files to be restored in "c:\TestFolders\FullSync" folder. Won't restore anything actually.

.EXAMPLE
restore-files-advanced.ps1 -Path 'c:\TestFolders\FullSync' -SearchDB -Database 'C:\ProgramData\Resilio\Connect Agent\4E1DB078C81BFB8D4ED16402E946964CE55D8440.35.db' -From "2021-09-21" -To "2021-09-30"
Restores files for sync folder "c:\TestFolders\FullSync" according to agent's database removed from Sep 21 to Sep 30

.EXAMPLE
restore-files-advanced.ps1 -JobName 'FullSy*' -SearchDB -WhatIf
Lists files that can be restored for sync job FullSync using agent's database

.EXAMPLE
restore-files-advanced.ps1 -ListJobs -Storage "F:\ResilioAgent2"
Lists jobs that secondary Agent (installed with storage path C:\ResilioAgen2) and displays their name and path for later usage with -JobName parameter.

.LINK
https://connect.resilio.com/hc/en-us/articles/115001291284-Understanding-the-Archive-folder
#>

[CmdletBinding(DefaultParameterSetName = 'ByFiles')]
param
(
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[string]$JobName,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[string]$Path,
	[Parameter(ParameterSetName = 'ByDB')]
	[string]$Database,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[switch]$WhatIf,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[string]$Log,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[string]$CSV,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[datetime]$From,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[datetime]$To,
	[Parameter(ParameterSetName = 'ByDB')]
	[switch]$SearchDB,
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[switch]$SupportLongPath,
	[Parameter(ParameterSetName = 'ListJobsOnly')]
	[switch]$ListJobs,
	[Parameter(ParameterSetName = 'ListJobsOnly')]
	[Parameter(ParameterSetName = 'ByFiles')]
	[Parameter(ParameterSetName = 'ByDB')]
	[string]$Storage
)



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
	if ($Path) { $global:bendata = Get-Content $Path -Raw }
	else { $global:bendata = [System.Text.Encoding]::GetEncoding("Windows-1251").GetString($BencodedData)}
	$global:Offset = 0
	$res = Get-BenValue
	return $res
}
# --------------------------------------------------------------------------------------------------------------------------------

function EnsurePathExist($path)
{
	$path_only = Split-Path -LiteralPath $path
	
	if (!(Test-Path $path_only))
	{
		New-Item -Path $path_only -ItemType Directory -Force | Out-Null
	}
}
#---------------------------------------------------------------------------------------------------------------------------------------

function CalculateUniqueFileName($path, $mtime) # Strips the (possible) versioning index from archived name, like "file.<index>.txt"
{
	$nameonly = ([io.fileinfo]$path).basename
	$pathonly = Split-Path -LiteralPath $path
	if ([string]::IsNullOrEmpty($pathonly)) { $name_and_path = "$nameonly" }
	else { $name_and_path = "$pathonly\$nameonly" }
	$extension = ([io.fileinfo]$path).Extension
	
	$a = $name_and_path -match "(.*?)(\.{1}(\d*))?$"
	
	$unique_name_path_ext = $matches[1] + $extension
	return $unique_name_path_ext
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

function Get-FoldersFromInternalConfig
{
	param
	(
		[string]$Storage,
		[switch]$UseCached
	)
	
	if ([string]::IsNullOrEmpty($Storage))
	{
		$tmp = Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\' -ErrorAction SilentlyContinue
		if ($tmp)
		{
			$Storage = "C:\ProgramData\Resilio\Connect Agent"
		}
		$tmp = Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio Inc.\Resilio Connect Console\' -ErrorAction SilentlyContinue
		if ($tmp)
		{
			$Storage = "C:\ProgramData\Resilio\Connect Server\Agent"
		}
	}
	if ([string]::IsNullOrEmpty($Storage))
	{
		Write-Error "Resilio Agent installation not found, specify storage path manually using `"-Storage`" parameter"
		return
	}
	$sync_dat_path = "$Storage\sync.dat"
	if (!(Test-Path -LiteralPath $sync_dat_path -PathType Leaf))
	{
		Write-Error "`"sync.dat`" file not found, likely storage was migrated manually to non-default location. Specify storage path manually using `"-Storage`" parameter."
		return
	}
	
	return (ConvertFrom-Bencode -Path $sync_dat_path).folders
}

#---------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------------------------------

Write-Host "Script to restore files from archive v2.2 started on $(Get-Date -Format G)"
$ownscriptpathname = $MyInvocation.MyCommand.Definition
$ownscriptpath = Split-Path -Path $ownscriptpathname
$ownscriptname = Split-Path $ownscriptpathname -Leaf

if ($ListJobs) # List jobs in sync.dat
{
	$Folders = Get-FoldersFromInternalConfig -Storage $Storage
	
	if ($Folders.Length -eq 0)
	{
		Write-Host "[No jobs]"
	}
	else
	{
		$Folders | Format-Table -Property @{ Label = 'Job name'; Expression = { $_.ui_name } }, @{ Label = 'Path'; Expression = { $_.pretty_path } } -AutoSize
	}
	return
}

if (![String]::IsNullOrEmpty($JobName)) # Find job path and database in sync.daat
{
	$Folders = Get-FoldersFromInternalConfig -Storage $Storage
	$MyFolder = $Folders | Where-Object { $_.ui_name -like $JobName }
	if ($MyFolder.Count -gt 1)
	{
		Write-Error "Too many jobs match the name"
		return
	}
	if ($MyFolder.Cound -eq 0)
	{
		Write-Error "Job with the name `"$JobName`" not found"
		return
	}
	$Path = $MyFolder.pretty_path
	$Database = Join-Path -Path $Storage -ChildPath $MyFolder.fc.db_name
	Write-Host "Found job `"$JobName`":"
	Write-Host "Path: `"$Path`""
    Write-Host "Database: `"$Database`""
}

if (!([System.IO.Path]::IsPathRooted($Path)))
{
	Write-Error "Synced folder path can't be relative"
	return
}

$Path = $Path.Trim('\')
if ($SupportLongPath)
{
	if ($PSVersionTable.PSVersion -lt "5.1")
	{
		Write-Error "Please update your Powershell to version 5.1 or newer for long paths support"
		return
	}
	$Path = "\\?\$Path"
}
$uniques = @{ }
$ArchivePath = "$Path\.sync\Archive"
$ArhivePathLen = $ArchivePath.Length + 1 # Include traling slash

if ([String]::IsNullOrEmpty($Log))
{
	$Log = "$ownscriptpath\restore-$(Split-Path $Path -Leaf).log"
}
if ([String]::IsNullOrEmpty($CSV))
{
	$CSV = "$ownscriptpath\archived-files-$(Split-Path $Path -Leaf).CSV"
}
$LoggerStream = New-Object System.IO.StreamWriter($Log)
$LoggerStream.Write("Script started on $(Get-Date -Format G)`n")
$CSVStream = New-Object System.IO.StreamWriter($CSV)
$CSVStream.Write("`"Status`", `"File path`", `"Archived path`", `"Archived time`"`n")
try
{
	if ($SearchDB) # Script runs in advanced mode to search removed file thru the Resilio DB
	{
		$tmp = Import-Module PSSqlite -ErrorAction SilentlyContinue -PassThru
		if (!$tmp)
		{
			Write-Error "SQLite module `"PSSQlite`" not found and it is mandatory to run the script. Use command `"Install-Module PSSQLite`" to install it in Powershell window with elevated privileges"
			return
		}
		$DBConnnection = New-SQLiteConnection -DataSource "$Database" -ReadOnly
		$tmp = Invoke-SqliteQuery -SQLiteConnection $DBConnnection -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='deleted_files2'"
		if (!$tmp)
		{
			Write-Error "The agent DB is too old and does not support advanced archived files restoring"
			return
		}
		$tmp = Invoke-SqliteQuery -SQLiteConnection $DBConnnection -Query "SELECT COUNT(*) FROM deleted_files2"
		$TotalEntries = $tmp.'COUNT(*)'
		Write-Host "Extracting $TotalEntries entries from database"
		$ArchivedFiles = Invoke-SqliteQuery -SQLiteConnection $DBConnnection -Query "SELECT * FROM deleted_files2"
		$EntryIndex = -1
		$OldEntryIndex = -1
		Write-Progress -Activity "Checking removed files" -PercentComplete 0
		foreach ($record in $ArchivedFiles)
		{
			$EntryIndex++
			if (($EntryIndex - $OldEntryIndex) -gt 10000)
			{
				Write-Progress -Activity "Checking removed files" -Status "Processed $EntryIndex of $TotalEntries" -PercentComplete (($EntryIndex * 100) / $TotalEntries)
				$OldEntryIndex = $EntryIndex
			}
			
			$unique_file_name = [System.Text.Encoding]::ASCII.GetString($record.original_path)
			$archived_file_path = [System.Text.Encoding]::ASCII.GetString($record.path)
			$archived_full_file_path = "$ArchivePath\$archived_file_path"
			$tmp_object = ConvertFrom-Bencode -BencodedData $record.data
			$archivation_time = ConvertFrom-UnixTime $tmp_object.mtime -ConvertToLocal
			if (!(Test-Path -LiteralPath $archived_full_file_path -PathType Leaf)) # File in achive does not exist, likely human interventon
			{
				$LoggerStream.Write("Missing file in archive: `"$archived_full_file_path`"`n")
				$CSVStream.Write("`"Missing`", `"$Path\$unique_file_name`", `"$archived_full_file_path`", `"$archivation_time`"`n")
				continue
			}
			UpdateUniqueList -unique_filename $unique_file_name -modification_time $archivation_time -archived_filename $archived_file_path
		}
		Write-Progress -Activity "Checking removed files" -Status "Processed $EntryIndex of $TotalEntries" -Completed
	}
	else # Script runs in a plain mode so we'll need to scan the archive folder manually
	{
		Write-Host "Listing files in archive..."
		$ArchivedFiles = Get-ChildItem -LiteralPath "$ArchivePath" -Recurse -Force | Where-Object { ! $_.PSIsContainer }
		Write-Host "Building list of unique files out of files versions..."
		foreach ($archived_file in $ArchivedFiles)
		{
			$RelativePath = "$($archived_file.FullName.Substring($ArhivePathLen))"
			$unique = CalculateUniqueFileName -path $RelativePath
			UpdateUniqueList -unique_filename $unique -modification_time $archived_file.LastWriteTime -archived_filename $RelativePath
		}
		
	}
	
	$EntryIndex = -1
	$OldEntryIndex = -1
	$TotalEntries = $uniques.Count
	$EntriesToRestore = 0
	$EntriesSuccessfullyRestored = 0
	if ($WhatIf)
	{
		Write-Host "Total files archived: $TotalEntries, listing suitable for restoring"
		$ActivityText = "Listing deleted files"
	}
	else
	{
		Write-Host "Total files archived: $TotalEntries, restoring"
		$ActivityText = "Restoring files"
	}
	Write-Progress -Activity $ActivityText -PercentComplete 0
	foreach ($key in $uniques.Keys)
	{
		$EntryIndex++
		if (($EntryIndex - $OldEntryIndex) -gt 1000) # Display progress for each 1K entries to not to consume too much performance
		{
			Write-Progress -Activity $ActivityText -Status "File $EntryIndex of $TotalEntries" -PercentComplete (($EntryIndex * 100) / $TotalEntries)
			$OldEntryIndex = $EntryIndex
		}
		$fileprops = $uniques[$key]
		$mtime = $fileprops['mtime']
		$archivedfile = $fileprops['archived_name']
		$fullarchivedpath = "$ArchivePath\$archivedfile"
		$real_position_path = "$Path\$key"
		
		if (Test-Path -LiteralPath $real_position_path -PathType Leaf)
		{
			# File exists outside of the archive, so it's just a version of non removed file
			$LoggerStream.Write("File `"$fullarchivedpath`" archived on $mtime exists outside archive and is just a version`n")
			$CSVStream.Write("`"Version`", `"$real_position_path`", `"$fullarchivedpath`", `"$mtime`"`n")
			continue
		}
		
		if ($From)
		{
			if ($mtime -lt $From)
			{
				$LoggerStream.Write("Ignoring (time) `"$fullarchivedpath`" archived on $mtime`n")
				$CSVStream.Write("`"Ignored`", `"$real_position_path`", `"$fullarchivedpath`", `"$mtime`"`n")
				continue
			}
		}
		if ($To)
		{
			if ($mtime -gt $To)
			{
				$LoggerStream.Write("Ignoring (time) `"$fullarchivedpath`" archived on $mtime`n")
				$CSVStream.Write("`"Ignored`", `"$real_position_path`", `"$fullarchivedpath`", `"$mtime`"`n")
				continue
			}
		}
		
		$EntriesToRestore++
		if ($WhatIf)
		{
			$LoggerStream.Write("File `"$real_position_path`" has been deleted. Can be restored from `"$fullarchivedpath`" archived on $mtime`n")
			$CSVStream.Write("`"ToRestore`", `"$real_position_path`", `"$fullarchivedpath`", `"$mtime`"`n")
		}
		else
		{
			$LoggerStream.Write("Restoring `"$fullarchivedpath`" to `"$real_position_path`" archived on $mtime`n")
			$CSVStream.Write("`"Restoring`", `"$real_position_path`", `"$fullarchivedpath`", `"$mtime`"`n")
			EnsurePathExist($real_position_path)
			Move-Item -LiteralPath $fullarchivedpath -Destination $real_position_path
			if ($?) { $EntriesSuccessfullyRestored++ }
			else { $LoggerStream.Write("Error restoring file: `"$($Error[0].Exception.Message)`"`n") }
		}
	}
	Write-Progress -Activity $ActivityText -Status "Restored $EntryIndex of $TotalEntries total" -Completed
	$msg = "Script planned to restore $EntriesToRestore of $TotalEntries, successfully restored $EntriesSuccessfullyRestored"
	Write-Host $msg
	$LoggerStream.Write("$msg`n")
}
catch
{
	$LoggerStream.Write("$_`n")
	Write-Error $_
}
finally
{
	$LoggerStream.Write("Script finished on $(Get-Date -Format G)`n")
	$LoggerStream.Close()
	$CSVStream.Close()
	if (Get-Module PSSQLite)
	{
		$DBConnnection.Close()
		Remove-Module PSSQLite
	}
	Write-Host "Script ended on $(Get-Date -Format G)"
}
