$ownscriptpathname = (Resolve-Path $MyInvocation.InvocationName).Path
$ownscriptpath = Split-Path -Path $ownscriptpathname
$ownscriptname = Split-Path $ownscriptpathname -Leaf

# Start logging
Start-Transcript -Path "$ownscriptpath\restart.log" -Append

Write-Verbose "Upgrade script started"
try
{
	$servicename = "connectsvc"
	$processname = "Resilio Connect Agent.exe"
	$processpath = (Get-ItemProperty -path 'HKLM:\SOFTWARE\Resilio, Inc.\Resilio Connect Agent\').InstallDir
	
    Write-Verbose "Found Agent installed to: $processpath"
	$fullexepath = Join-Path -Path $processpath -ChildPath $processname
	
	# Stop Agent service
	Write-Verbose "Stopping agent service..."
	Stop-Service -Name $servicename
	
	# Give it some minutes to end in case it got really large DB
	$timer = [system.diagnostics.stopwatch]::StartNew()
	while ($timer.Elapsed.Minutes -lt 10)
	{
		$srv = Get-Service -Name $servicename
		if ($srv.Status -eq 'Stopped')
		{
			Write-Verbose "Agent service stopped gracefully"
			break
		}
		Start-Sleep 1
	}
	$timer.Stop
	
	# If it hangs, kill the process forcefully
	if ($timer.Elapsed.Minutes -ge 10)
	{
		Stop-Process -Name $processname -Force
		Write-Verbose "Agent service failed to stop, killing process"
	}
}
catch
{
	Write-Error "Unexpected error occuerd: $_"
}
finally
{
	# Start Agent service
	Start-Service -Name $servicename
	Write-Verbose "Agent service started"
	
	# Stop logging
	Write-Verbose "Finishing logging"
	Stop-Transcript
}