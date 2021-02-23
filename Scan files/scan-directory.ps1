[CmdletBinding()]
param
(
	[parameter(Mandatory = $true)]
	[String]$Path,
	[int]$FilesAmountExpected = 1000000,
	[switch]$SupportLongPath
)

# ----------------------------------------------------------------------------------------------------------------------------------------

function Traverse-Directory
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToProcess
	)
	
	$FilesList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes !Directory
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	$DirsList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes Directory
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	
	foreach ($file in $FilesList)
	{
		#Process-Item $file.FullName
		$script:TotalSize += $file.Length
	}
	foreach ($dir in $DirsList)
	{
		#Process-Item $dir.FullName
	}
	$script:FileCounter += $FilesList.Count
	$script:DirCounter += $DirsList.Count
	if ($script:FileCounter -gt $FilesAmountExpected) { $FilesAmountExpected += 10000 }
#	Write-Progress -Activity "Traversing directories recursively" -Status "Processed $($script:FileCounter) files, $($script:DirCounter) directories" -PercentComplete ($script:FileCounter * 100 / $FilesAmountExpected)
	foreach ($dir in $DirsList)
	{
		Traverse-Directory -PathToProcess $dir.FullName
	}
}
# ----------------------------------------------------------------------------------------------------------------------------------------

$FileCounter = 0
$DirCounter = 0
$ItemsUpdated = 0
$UnsuccesfulUpdates = 0
$TotalSize = 0

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

if ($SupportLongPath) { $Path = "\\?\$Path" }

Traverse-Directory -PathToProcess $Path
#Write-Progress -Activity "Traversing directories recursively" -Completed
Write-Host "Total files $FileCounter; dirs: $DirCounter; size: $TotalSize"
