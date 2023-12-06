<#
.SYNOPSIS
This script it intended to reveal true disk access speed in terms of both data read speed and amount of files read

.DESCRIPTION
Majority of modern storages like NetAPP, Nimble and others have extensive caches and do not respect WinAPI calls which attempt
to avoid caching. As a result, standard applications like diskspd.exe and others has not chances to bypass the cache and
measure real performance of your storage.
This script is reading real files on your filesystem in memory. Therefore, after some time it will exhaust the storage device
cache and show it's real performance. 
It only measures 2 metrics: total disk read speed in bytes per second and files per second. It's recommended to pay attention
only to X-sec window results and only why they become stable. It makes no big sense to look at average values as they are
distorted with cache performance (counted since very beginning of the test)

.PARAMETER Path
Specify the path to a folder with the data for script to read. It won't modify any files, just open-read-close.

.PARAMETER BlockSize
Specify the block size in bytes the script will use to read files. If you are measuring against some software (like
Resilio Connect Agent) - pick the same block size it is going to use.

.PARAMETER WindowSize
Specify the time window size in seconds. The script will only grab last X seconds of measurements then showing the
stable speed metrics and therefore will drop all the values distorted by your storage cache.

.EXAMPLE
.\disk-speed.ps1 -Path F:\MyFolder -WindowSize 60
Runs script to measure drive F:\ performance on files in F:\Myfolder. The window metrics will only show last 60 seconds average measurements.
#>
[CmdletBinding()]
param
(
	[parameter(Mandatory = $true)]
	[String]$Path,
	[int64]$BlockSize = 1048576,
	[int]$WindowSize = 10
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
	
	if ($script:StopWatch.Elapsed.Seconds -ne $script:old_sec)
	{
		$script:old_sec = $script:StopWatch.Elapsed.Seconds
		$SecondsElapsed = $script:StopWatch.Elapsed.TotalSeconds
		$BytesPerSecond = ($script:TotalSize / $SecondsElapsed).ToString("#")
		$FilePerSecond = ($script:FileCounter / $SecondsElapsed).ToString("#")
		$SecondsElapsedStr = ($SecondsElapsed).ToString("#.#")
		
		# Here goes calculation of stats for only last X seconds
		$script:MeasureLog.Add( @{ Time = $SecondsElapsed; Data = $script:TotalSize; Files = $script:FileCounter } ) | Out-Null
		$i = $script:MeasureLog.Count - 1
		while (($SecondsElapsed - $script:MeasureLog[$i].Time) -lt $WindowSize)
		{
			$i--
			if ($i -eq -1) { break }
		}
		if ($i -eq -1) { $AddOn = "-------" }
		else
		{
			$WinTimeElapsed = $SecondsElapsed - $script:MeasureLog[$i].Time
			$script:WinBytes = (($script:TotalSize - $script:MeasureLog[$i].Data) / $WinTimeElapsed).ToString("#")
			$script:WinFiles = (($script:FileCounter - $script:MeasureLog[$i].Files) / $WinTimeElapsed).ToString("#")
			$AddOn="$($script:WinBytes) b/sec; $($script:WinFiles) files/sec"
		}
		Write-Host "Files processed: $($script:FileCounter) in $SecondsElapsedStr seconds; $BytesPerSecond b/sec; $FilePerSecond files/sec; $WindowSize-sec window: $AddOn"
	}
	
	foreach ($file in $FilesList)
	{
		
		$FileReadStream = [System.IO.File]::OpenRead($file.FullName)
		
		$BytesRead = $FileReadStream.Read($script:tmp_data_buf, 0, $BlockSize)
		while ($BytesRead -gt 0)
		{
			$BytesRead = $FileReadStream.Read($script:tmp_data_buf, 0, $BlockSize)
		}
		$FileReadStream.Close()
		$script:TotalSize += $file.Length
	}
	$script:FileCounter += $FilesList.Count
	foreach ($dir in $DirsList)
	{
		Traverse-Directory -PathToProcess $dir.FullName
	}
	$script:DirCounter += $DirsList.Count
}
# ----------------------------------------------------------------------------------------------------------------------------------------

$FileCounter = 0
$DirCounter = 0
$TotalSize = 0
$WinBytes = 0
$WinFiles = 0
$old_sec = 0
$StopWatch = [system.diagnostics.stopwatch]::StartNew()
$MeasureLog = [System.Collections.ArrayList]@()
$tmp_data_buf = New-Object byte[] $BlockSize

Write-Host "Measuring disk performance on real data set in folder `"$Path`""

try
{
	Traverse-Directory -PathToProcess $Path
}
finally
{
	$StopWatch.Stop()
	$BytesPerSecond = ($TotalSize / $StopWatch.Elapsed.TotalSeconds).ToString("#.#")
	$FilePerSecond = ($FileCounter / $StopWatch.Elapsed.TotalSeconds).ToString("#.#")
	$DurationStr = ($StopWatch.Elapsed.TotalSeconds).ToString("#.#")
	Write-Host "Test duration:             $($StopWatch.Elapsed.TotalSeconds) seconds"
	Write-Host "Total files read:          $FileCounter"
	Write-Host "Total data:                $TotalSize bytes"
	Write-Host "Average read speed:        $BytesPerSecond b/sec"
	Write-Host "Average file access speed: $FilePerSecond files/sec"
	Write-Host "Stable read speed:         $WinBytes b/sec"
	Write-Host "Stable file access speed:  $WinFiles files/sec"
}



