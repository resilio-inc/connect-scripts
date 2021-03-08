<#
.SYNOPSIS
This script is intended to control which files and folders are (going) to be be synced as well as check which are ignored

.DESCRIPTION
There ar 2 major uses for this script:
- Verify which files are to be synced and which to be ignored due to IgnoreList or due to staying in .sync folder. Run it with -Path and -OutFile parameters to
scan the folder. It will create several text files containing lists of files to be synced or ignored. Each entry contains filename, size and modificaiton time. 
The script will use these attributes to compare directories in its 2nd use case.
- Compare the difference between 2 directories. 
The script knows how to list files in deep directories (with path greater than 260 symbols). Use the parameter -SupportLongPath if you suspect you've got long paths.
The script warns if it encounters insufficient permissions or other errors so you can check them manually
It is recommended to run the script under same user account your Agent runs so it will warn you about any permissions error it encounters.
The script is performance and RAM optimized and is capable to handle up to 10M of files given enough time.

.PARAMETER Path
Specify the path to a folder to be scanned.

.PARAMETER OutPath
Specify the folder for scan results. Scan results are several text files with the name of folder specified in -Path parameter

.PARAMETER SupportLongPath
Specify to allow script working with paths longer than 260 symbols. Requires powershell 5.1 and newer! Won't work on PS4.

.PARAMETER FileListA
Specify the output text file provided in SCAN to compare if your folders match and to see what is the difference.

.PARAMETER FilesListB
Specify the output text file provided in SCAN of the same folder on another computer.

.OUTPUTS
<synced_folder_name>-synced.txt     Contains list of files that should be synced by Agents
<synced_folder_name>-dot-sync.txt   Contains list of files that stay in .synd folder and won't be synced
<synced_folder_name>-ignored.txt    Contains list of files ignored via default IgnoreList
<synced_folder_name>-perms.txt      Contains list of files script was unable to list due to permissions

.LINK 
https://github.com/resilio-inc/connect-scripts/tree/master/Scan%20files

.EXAMPLE
.\scan-directory.ps1 -Path F:\MyFolder -OutPath C:\Support -SupportLongPath
Scans the F:\MyFolder for files that will be synced and that will be ignored. Will respect long paths and save the results in
C:\Support\MyFolder-synced.txt
C:\Support\MyFolder-dot-sync.txt  
C:\Support\MyFolder-ignored.txt   
C:\Support\MyFolder-perms.txt     
respectively. See the outputs help section for details of each file.

.EXAMPLE
.\scan-directory.ps1 -FileListA C:\Support\MyFolder-synced.txt -FileListB "\\myserver\c$\Support\MyFolder-synced.txt"
Compares 2 scans on 2 different computer and profives a difference, i.e. files that were not synced for some reason.
#>
[CmdletBinding()]
param
(
	[parameter(ParameterSetName = "Scan", Mandatory = $true)]
	[String]$Path,
	[parameter(ParameterSetName = "Scan", Mandatory = $true)]
	[String]$OutPath,
	[parameter(ParameterSetName = "Scan")]
	[switch]$SupportLongPath,
	[parameter(ParameterSetName = "Compare")]
	[String]$FilesListA,
	[parameter(ParameterSetName = "Compare")]
	[String]$FilesListB
)

# ----------------------------------------------------------------------------------------------------------------------------------------

function CheckIgnored
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$EntryName
	)
	
	if ($EntryName -like ".sync") { return 2 }
	foreach ($filter in $script:ignorelist)
	{
		if ($EntryName -like $filter) { return 3 }
	}
	return 0
}
# ----------------------------------------------------------------------------------------------------------------------------------------

function Traverse-Directory
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToProcess,
		[int]$IgnoreReason = 0
	)
	
	$FilesList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes !Directory
	if (!$?)
	{
		$RelativePath = ".\$($PathToProcess.Substring($PathLen))"
		$script:IgnoreCounter[4]++
		$StreamWriter[4].Write("$RelativePath`n")
		Write-Error "Failed to GCI: $PathToProcess"
	}
	$DirsList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes Directory
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	
	$script:FileCounter += $FilesList.Count
	$script:DirCounter += $DirsList.Count
	
	if (($script:FileCounter - $script:old_fc) -gt 10000) # Display some progress here
	{
		Write-Host "Files processed: $($script:FileCounter)`r" -NoNewline
		$script:old_fc = $script:FileCounter
	}
	
	if ($IgnoreReason -ne 0) # This directory already ignored, no point in running any verifications
	{
		$script:IgnoreCounter[$IgnoreReason] += $FilesList.Count
		$script:IgnoreCounter[$IgnoreReason] += $DirsList.Count
		foreach ($file in $FilesList)
		{
			$RelativePath = ".\$($file.FullName.Substring($PathLen))"
			
			$StreamWriter[$IgnoreReason].Write("$RelativePath $($file.Length) $($file.LastWriteTime.ToString())`n")
			$script:TotalSize += $file.Length
			$script:IgnoreCounterSize[$IgnoreReason] += $file.Length
		}
		foreach ($dir in $DirsList)
		{
			$RelativePath = ".\$($dir.FullName.Substring($PathLen))"
			$StreamWriter[$IgnoreReason].Write("$RelativePath`n")
			Traverse-Directory -PathToProcess $dir.FullName -IgnoreReason $IgnoreReason
		}
	}
	else # Here we are dealing with not-yet-ignored files and folders and need to verify each against the filter(s)
	{
		foreach ($file in $FilesList)
		{
			$RelativePath = ".\$($file.FullName.Substring($PathLen))"
			#$IgnoreReasonTmp = CheckIgnored $file.Name $file.LastAccessTimeUtc
			$IgnoreReasonTmp = CheckIgnored $file.Name
			$script:IgnoreCounter[$IgnoreReasonTmp]++
			$script:IgnoreCounterSize[$IgnoreReasonTmp] += $file.Length
			
			$StreamWriter[$IgnoreReasonTmp].Write("$RelativePath $($file.Length) $($file.LastWriteTime.ToString())`n")
			$script:TotalSize += $file.Length
		}
		foreach ($dir in $DirsList)
		{
			$RelativePath = ".\$($dir.FullName.Substring($PathLen))"
			$IgnoreReasonTmp = CheckIgnored $dir.Name
			$script:IgnoreCounter[$IgnoreReasonTmp]++
			
			$StreamWriter[$IgnoreReasonTmp].Write("$RelativePath`n")
			Traverse-Directory -PathToProcess $dir.FullName -IgnoreReason $IgnoreReasonTmp
		}
	}
}
# ----------------------------------------------------------------------------------------------------------------------------------------

# Ignore Reasons:
# 0 - not ignored
# 1 - Due to "Max file age"
# 2 - Due to staying in ".sync" subfolder
# 3 - Due to default IgnoreList
# 4 - Due to unable to access (insufficient permissions or long paths are the most popular reasons)

$IgnoreNames = @("synced", "old", "dot-sync", "ignored", "perms")
$IgnoreCounter = @(0, 0, 0, 0, 0)
$IgnoreCounterSize = @(0, 0, 0, 0, 0)

$FileCounter = 0
$DirCounter = 0
$ItemsUpdated = 0
$UnsuccesfulUpdates = 0
$TotalSize = 0
$old_fc = 0

$ignorelist = @('$RECYCLE.BIN',
	'$Recycle.Bin',
	'System Volume Information',
	'ehthumbs.db',
	'desktop.ini',
	'Thumbs.db',
	'lost+found',
	'.DocumentRevisions-V100',
	'.TemporaryItems',
	'.fseventsd',
	'.iCloud',
	'.DS_Store',
	'.DS_Store?',
	'.Spotlight-V100',
	'.Trashes',
	'.Trash-*',
	'~*',
	'*~',
	'.~lock.*',
	'*.part',
	'*.filepart',
	'.csync_journal.db',
	'.csync_journal.db.tmp',
	'*.swn',
	'*.swp',
	'*.swo',
	'*.crdownload',
	'.@__thumb',
	'.thumbnails',
	'._*',
	'*.tmp',
	'*.tmp.chck',
	'.dropbox',
	'.dropbox.attr',
	'.dropbox.cache',
	'.streams',
	'.caches',
	'.Statuses',
	'.teamdrive',
	'.SynologyWorkingDirectory',
	'@eaDir',
	'@SynoResource',
	'#SynoRecycle',
	'#snapshot',
	'#recycle',
	'.!@#$recycle',
	'DfsrPrivate')

if ($PSCmdlet.ParameterSetName -eq "Scan")
{
	Write-Host "Scanning folder"
	$ScanFolderName = $Path | Split-Path -Leaf
	$Path = $Path.Trim('\') + "\"
	if ($SupportLongPath) { $Path = "\\?\$Path" }
	$PathLen = $Path.Length
	$StreamWriter = @()
	
	try
	{
		for ($i = 0; $i -lt 5; $i++)
		{
			$StreamWriter += new-object system.IO.StreamWriter($OutPath + "\$ScanFolderName-$($IgnoreNames[$i]).txt")
		}
		Traverse-Directory -PathToProcess $Path
	}
	finally
	{
		for ($i = 0; $i -lt 5; $i++)
		{
			$StreamWriter[$i].close()
		}
	}
	Write-Host "Total files: $FileCounter, size: $TotalSize"
	Write-Host "Total directories: $DirCounter"
	Write-Host "Entries to be synced: $($IgnoreCounter[0]), size: $($IgnoreCounterSize[0])"
	Write-Host "Entries to be ignored: $($IgnoreCounter[1] + $IgnoreCounter[2] + $IgnoreCounter[3] + $IgnoreCounter[4]), size $($IgnoreCounterSize[1] + $IgnoreCounterSize[2] + $IgnoreCounterSize[3] + $IgnoreCounterSize[4])"
	Write-Host "Ignored due to staying in .sync folder: $($IgnoreCounter[2]), size: $($IgnoreCounterSize[2])"
	Write-Host "Ignored due to default IgnoreList: $($IgnoreCounter[3]), size: $($IgnoreCounterSize[3])"
	Write-Host "Ignored due to inability to open*: $($IgnoreCounter[4])"
	Write-Host " * Likely due to insufficient permissions. Note, that there could be more files/folders, actually as script was unable to list all files"
}

if ($PSCmdlet.ParameterSetName -eq "Compare")
{
	Write-Host "Loading `"$FilesListA`""
	$ListA = Get-Content $FilesListA
	Write-Host "Loading `"$FilesListB`""
	$ListB = Get-Content $FilesListB
	Write-Host "Comparing 2 lists"
	$CmpResult = Compare-Object $ListA $ListB
	Write-Host "Left is `"$FilesListA`", right is `"$FilesListB`""
	$CmpResult | Sort-Object -Property InputObject
}



