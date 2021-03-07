[CmdletBinding()]
param
(
	[parameter(Mandatory = $true)]
	[String]$Path,
	[String]$OutPath,
	[int]$FilesAmountExpected = 1000000,
	[switch]$SupportLongPath
)

# ----------------------------------------------------------------------------------------------------------------------------------------

function CheckIgnored
{
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
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	$DirsList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes Directory
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	
	$script:FileCounter += $FilesList.Count
	$script:DirCounter += $DirsList.Count
	
	if (($script:FileCounter - $script:old_fc) -gt 10000) # Display some progress here
	{
		#Write-Host "Files processed: $($script:FileCounter)    `r" -NoNewline
		Write-Progress -Activity "Scanning folder" -Status "Processed $($script:FileCounter) files, $($script:DirCounter) directories" -PercentComplete ($script:FileCounter * 100 / $FilesAmountExpected) -ErrorAction SilentlyContinue
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
			$IgnoreReasonTmp = CheckIgnored $RelativePath $file.LastAccessTimeUtc
			$script:IgnoreCounter[$IgnoreReasonTmp] ++
			
			$StreamWriter[$IgnoreReasonTmp].Write("$RelativePath $($file.Length) $($file.LastWriteTime.ToString())`n")
			$script:TotalSize += $file.Length
		}
		foreach ($dir in $DirsList)
		{
			$RelativePath = ".\$($dir.FullName.Substring($PathLen))"
			$IgnoreReasonTmp = CheckIgnored $RelativePath
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

$ScanFolderName = $Path | Split-Path -Leaf
$OutFileName = $OutPath + "\$ScanFolderName-list.txt"
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
Write-Progress -Activity "Scanning folder" -Completed
Write-Host "Total files $FileCounter; dirs: $DirCounter; size: $TotalSize"
