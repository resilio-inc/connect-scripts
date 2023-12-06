<#
.SYNOPSIS
The script goes over directories tree recursively, and fixing mtime for all files where it is invalid.

.DESCRIPTION
"Invalid" permission is the one where Epoch time for it equal zero, below zero or is in future comparing to current time

.PARAMETER Path
Specify to point the directory to be inspected for missing permissions.

.PARAMETER FilesAmountExpected
Specify approximate amount of files for correct progress bar behavior

.PARAMETER WhatIf
Specify to only show which files are going to be updated and don't do actual changes to filesystem. 

.PARAMETER SupportLongPath
Specify to allow script working with paths longer than 260 symbols. Requires powershell 5.1 and newer! Won't work on PS4.

.EXAMPLE
.\fix-mtime.ps1 -Path C:\TestFolders\ -SupportLongPath *>log.txt
will run the scrip to process C:\TestFolders and all its children recursively adding SYSTEM:FullControl permission to all items, assigning current user as an owner if necessary and dumping successful/unsuccesful attempts into file log.txt
#>

[CmdletBinding()]
param
(
	[parameter(Mandatory = $true)]
	[String]$Path,
	[int]$FilesAmountExpected = 10000000,
	[switch]$WhatIf,
	[switch]$TakeOwnership,
	[switch]$SupportLongPath,
	[string]$TargetUser = "NT AUTHORITY\SYSTEM"
)

# ----------------------------------------------------------------------------------------------------------------------------------------

function Process-Item
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToItem
	)
	
	$Item = Get-Item -LiteralPath $PathToItem
	if ($Item.LastWriteTime -gt (Get-Date).AddMinutes(1))
	{
		$Script:ItemsToFix++
		if ($WhatIf)
		{
			Write-Host "Future timestamp found ($($Item.LastWriteTime.ToString()) for file $($Item.FullName)"
		}
		else
		{
			Write-Host "Fixing future timestamp ($($Item.LastWriteTime.ToString()) for file $($Item.FullName)"
			$Item.LastWriteTime = Get-Date
			$Script:ItemsUpdated++
		}
	}
	if ($Item.LastWriteTime -le $Script:EpochStart)
	{
		$Script:ItemsToFix++
		if ($WhatIf)
		{
			Write-Host "Zero or invalid time found ($($Item.LastWriteTime.ToString()) for file $($Item.FullName)"
		}
		else
		{
			Write-Host "Fixing zero or invalid time ($($Item.LastWriteTime.ToString()) for file $($Item.FullName)"
			$Item.LastWriteTime = Get-Date
			$Script:ItemsUpdated++
		}
	}
	
}
# ----------------------------------------------------------------------------------------------------------------------------------------

function Traverse-Directory
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToProcess
	)
	$FilesList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes !Directory -ErrorAction SilentlyContinue
	if (!$?)
	{
		Write-Error "Failed to list files in: $PathToProcess ($($Error[0].ToString()))"
	}
	else
	{
		foreach ($file in $FilesList)
		{
			Process-Item $file.FullName
		}
		$script:FileCounter += $FilesList.Count
	}
	
	$DirsList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes Directory -ErrorAction SilentlyContinue
	if (!$?)
	{
		Write-Error "Failed to list directories in: $PathToProcess ($($Error[0].ToString()))"
	}
	else
	{
		foreach ($dir in $DirsList)
		{
			Traverse-Directory -PathToProcess $dir.FullName
		}
		$script:DirCounter += $DirsList.Count
	}
	
	if ($script:FileCounter -gt $FilesAmountExpected) { $FilesAmountExpected = $script:FileCounter + 10000}
	Write-Progress -Activity "Searching for invalid mtime" -Status "Processed $($script:FileCounter) files, $($script:DirCounter) directories" -PercentComplete ($script:FileCounter * 100 / $FilesAmountExpected)
}
# ----------------------------------------------------------------------------------------------------------------------------------------

Write-Host "Script version 1.0 (2023-03-14) started"
Write-Host "Will scan for mtime errors for `"$Path`""
$FileCounter = 0
$DirCounter = 0
$ItemsUpdated = 0
$ItemsToFix = 0
$EpochStart = [DateTime]"1970.01.01 00:00:00"

$Path = $Path.Trim('\') + "\"
if ($SupportLongPath)
{
	if ($PSVersionTable.PSVersion -lt "5.1")
	{
		throw "Powershell is too old: please update your Powershell to version 5.1 or newer for long paths support"
	}
	$Path = "\\?\$Path"
}

Write-Host "Searching for invalid mtime values..."
Traverse-Directory -PathToProcess $Path
Write-Progress -Activity "Searching for invalid mtime" -Completed

Write-Host "Processed total $FileCounter files, $DirCounter dirs. Files to update: $ItemsToFix, updated files: $ItemsUpdated"

