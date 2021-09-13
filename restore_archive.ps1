<#
.SYNOPSIS 
Script is intended to restore deleted files from Resilio Connect or Resilio Sync archive folder

.DESCRIPTION
Script is intended to restore deleted files from archive. If multiple versions of a file exist, 
only the newest (depending on modification time) will get restored. If versioned file exists on 
according path outside of archive, script won't restore it.

.PARAMETER action
Could take one of the following
   analyze - simply shows which files script is going to restore
   restore - actually move files from <path_to_synced_folder>\.sync\Archive to <path_to_synced_folder>

.PARAMETER synced_folder_path
Specifies full path to synced folder. 
#>

Param(
  [string]$action,
  [string]$synced_folder_path,
  [switch]$SupportLongPath
)

function CalculateUniqueFileName($path, $mtime)
{
$nameonly = ([io.fileinfo]$path).basename
$pathonly = Split-Path -LiteralPath $path
$name_and_path = Join-Path -path $pathonly -ChildPath $nameonly
$extension = ([io.fileinfo]$path).Extension

$a = $name_and_path -match "(.*?)(\.{1}(\d*))?$" 

$unique_name_path_ext = $matches[1]+$extension
return $unique_name_path_ext
}
#---------------------------------------------------------------------------------------------------------------------------------------

function EnsurePathExist($path)
{
$path_only = Split-Path -Path $path

if(!(Test-Path $path_only))
    {
    New-Item -Path $path_only -ItemType Directory -Force | Out-Null
    }
}
#---------------------------------------------------------------------------------------------------------------------------------------

function UpdateUniqueList($unique_filename, $modification_time, $archived_filename)
{
$uniquefileprops = @{
    'mtime' = $modification_time
    'archived_name' = $archived_filename
    'status' = "unknown"
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

#$synced_folder_path = "c:\ABC"
#$action = "restore"

$synced_folder_path = $synced_folder_path.Trim('\') + "\"
if ($SupportLongPath) { $synced_folder_path = "\\?\$synced_folder_path" }

$need_to_exit = $false

if ([string]::IsNullOrEmpty($synced_folder_path))
    {
    Write-Host error: `-synced_folder_path paramter is empty
    $need_to_exit = $true
    }

if ([string]::IsNullOrEmpty($action))
    {
    Write-Host error: `-action parameter cannot be empty, must be either `"analyze`" or `"restore`"
    $need_to_exit = $true
    }

if ($need_to_exit)
    {
    return
    }

$archive_path = "$synced_folder_path.sync\Archive"
$ArhivePathLen = $archive_path.Length

$archived_files = Get-ChildItem -path "$archive_path" -recurse -force | Where-Object { ! $_.PSIsContainer }
$uniques = @{}

foreach($archived_file in $archived_files)
    {
	#$relativepath = Resolve-Path -LiteralPath $archived_file.FullName -Relative
	$RelativePath = ".\$($archived_file.FullName.Substring($ArhivePathLen+1))"
	#Write-Host "DEBUG: Relative path is $RelativePath"
	
	$unique = CalculateUniqueFileName -path $RelativePath
	#Write-Host "DEBUG: Unique is $unique"
	UpdateUniqueList -unique_filename $unique -modification_time $archived_file.LastWriteTime -archived_filename $RelativePath
    }

foreach($key in $uniques.Keys)
    {
    $fileprops = $uniques[$key]
    $mtime = $fileprops['mtime']
    $archivedfile = $fileprops['archived_name']
    $fullarchivedpath = "$archive_path$($archivedfile.Substring(1))"
	$real_position_path = "$synced_folder_path$($key.SubString(2))"
#	if ($mtime -lt "2021-01-01" -or $mtime -gt "2021-09-20")
#	{
#		Write-host "Skipping $fullarchivedpath - archived on $mtime"
#		continue
#	}
    if (Test-Path -LiteralPath $real_position_path -PathType Leaf)
        {
        $uniques[$key]['status'] = 'exists'
        }
        else 
        {
        $uniques[$key]['status'] = 'deleted'
        }
    if ($action -eq 'analyze')
        {
        if ($uniques[$key]['status'] -eq 'deleted')
            {
            Write-host File $real_position_path has been deleted. Can be restored from $fullarchivedpath, which was last modified on $mtime
            }
        if ($uniques[$key]['status'] -eq 'exists')
            {
            Write-host File $real_position_path still exists. Archive contains version $fullarchivedpath, which was last modified on $mtime
            }
        }
    if ($action -eq 'restore')
        {
        if ($uniques[$key]['status'] -eq 'deleted')
            {
            Write-host Restoring $fullarchivedpath to $real_position_path last changed on $mtime
            EnsurePathExist($real_position_path)
            Move-Item -LiteralPath $fullarchivedpath -Destination $real_position_path
            }
        }
    }
    