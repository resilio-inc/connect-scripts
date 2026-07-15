function Get-SystemMemoryResult {
	try 
	{
		$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
		$memoryGb = [Math]::Round(($computerSystem.TotalPhysicalMemory / 1GB), 2)

		return @(
			[PSCustomObject]@{
				Check  = "System.Memory"
				Status = "PASS"
				Detail = "Total physical memory: $memoryGb GB"
			}
		)
	}
	catch
	{
		return @(
			[PSCustomObject]@{
				Check  = "System.Memory"
				Status = "FAIL"
				Detail = "Unable to read memory information: $($_.Exception.Message)"
			}
		)
	}
}

function Get-SystemDiskResult {
	try
	{
		$startedDrive = [System.IO.Path]::GetPathRoot((Get-Location).Path).TrimEnd('\\')
		$logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk `
			-Filter "DriveType = 3 AND DeviceID = '$startedDrive'" `
			-ErrorAction Stop

		if (-not $logicalDisk)
		{
			throw "Logical disk '$startedDrive' was not found."
		}

		$totalDiskGb = [Math]::Round(($logicalDisk.Size / 1GB), 2)

		return @(
			[PSCustomObject]@{
				Check  = "System.Disk"
				Status = "PASS"
				Detail = "Logical disk size ($startedDrive): $totalDiskGb GB"
			}
		)
	}
	catch
	{
		return @(
			[PSCustomObject]@{
				Check  = "System.Disk"
				Status = "FAIL"
				Detail = "Unable to read disk information: $($_.Exception.Message)"
			}
		)
	}
}

function Get-SystemCpuResult {
	try
	{
		$processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
		$totalCores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum

		return @(
			[PSCustomObject]@{
				Check  = "System.CPU"
				Status = "PASS"
				Detail = "Total CPU cores: $totalCores"
			}
		)
	}
	catch
	{
		return @(
			[PSCustomObject]@{
				Check  = "System.CPU"
				Status = "FAIL"
				Detail = "Unable to read CPU information: $($_.Exception.Message)"
			}
		)
	}
}

function Invoke-RslCheckSystem {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Config
	)

	Write-Host "Checking System..."

	$results = @()
	$results += Get-SystemMemoryResult
	$results += Get-SystemDiskResult
	$results += Get-SystemCpuResult

	$results
}

Export-ModuleMember -Function Invoke-RslCheckSystem
