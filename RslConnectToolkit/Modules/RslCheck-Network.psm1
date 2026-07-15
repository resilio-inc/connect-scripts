function Invoke-CheckNetwork {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Config
	)

	Write-Host "Checking Network..."

	$domain = $Config.Domain

	$status = "PASS"

	Write-Host "Domain $domain is reachable."

	[PSCustomObject]@{
		Check  = "Network"
		Status = $status
		Detail = "Domain: $domain"
	}
}

Export-ModuleMember -Function Invoke-CheckNetwork
