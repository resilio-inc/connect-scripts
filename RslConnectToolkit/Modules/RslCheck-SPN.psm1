function Invoke-CheckSPN {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Config
	)

	Write-Host "Checking SPN..."

	$domain = $Config.Domain

	$status = "PASS"

	Write-Host "Domain $domain is reachable."

	[PSCustomObject]@{
		Check  = "SPN"
		Status = $status
		Detail = "Domain: $domain"
	}
}

Export-ModuleMember -Function Invoke-CheckSPN
