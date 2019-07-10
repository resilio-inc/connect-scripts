# Please adjust parameters below to adjust script behavior to your needs
$path_to_observe = "."
$path_to_move_files_to = "C:\Test7\"
$exit_counter_seconds = 600
$step_seconds = 5
$keep_path = $false
$clean_empty_folders = $true

# Script start
Set-Location $path_to_observe

# Check if previous instance of that script is still running - and kill it if it does
$PID_file = "$path_to_observe\.sync\move-arriving-files.pid"
$old_pid = Get-Content $PID_file -ErrorAction SilentlyContinue
if ($old_pid)
{
	$old_ps = Get-Process | where { $_.id -eq $old_pid }
	if ($old_ps -and $old_ps.processname -like "powershell")
	{
		$old_ps | Stop-Process -Force
		Write-Output "Script detected old instance with PID $($old_ps.id) powershell running, killed"
	}
}
Set-Content -Path $PID_file -Value $pid

# Start monitoring the folder for arriving files
try
{
	while ($exit_counter_seconds -gt 0)
	{
		$files = Get-ChildItem -Path $path_to_observe -Recurse -Attributes !Directory -Force | where { $_.FullName -notlike "*\.sync\*" }
		foreach ($file in $files)
		{
			if ($keep_path) # Move files in complex way, retaining the path
			{
				$relativepath = Resolve-Path -LiteralPath $file.FullName -Relative
				$tmp = Join-Path -Path $path_to_move_files_to -ChildPath $relativepath
				$newpath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($tmp) #Fixes redundant dots in path
				$path_only = Split-Path -Path $newpath
				if (!(Test-Path $path_only)) # If target path does not exist
				{
					New-Item -Path $path_only -ItemType Directory -Force | Out-Null
				}
				# Marker 1: Adjust action script takes on a new file here (when keeping the path)
				Move-Item -LiteralPath $file.FullName -Destination $newpath -Force
			}
			else # Move files in a simple way, to root destination directory
			{
				# Marker 2: Adjust action script takes on a new file here (when source file path discarded)
				Move-Item -Path $file.FullName -Destination (Join-Path $path_to_move_files_to $file.Name) -Force
			}
			Write-Output "Found new file `"$($file.Name)`", moving"
		}
		if ($clean_empty_folders) # Clean empty folders if they are no longer required by user
		{
			$folders = Get-ChildItem -Path $path_to_observe -Recurse -Attributes Directory | where { $_.FullName -notlike "*\.sync*" }
			foreach ($folder in $folders)
			{
				if ((Get-ChildItem -Path $folder.FullName -Force).Length -eq 0)
				{
					Remove-Item $folder.FullName -Recurse
					Write-Output "Cleaning folder `"$($folder.FullName)`" as it is empty"
				}
			}
		}
		$exit_counter_seconds = $exit_counter_seconds - $step_seconds
		Start-Sleep -Seconds $step_seconds
	}
}
finally
{
	Remove-Item $PID_file -Force
}

