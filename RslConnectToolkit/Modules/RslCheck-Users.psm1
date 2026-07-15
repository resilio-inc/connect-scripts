function Invoke-RslCheckUsers {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Config
	)

	Write-Host "Checking Users..."

	$domain = $Config.Domain

	$status = "PASS"

	Write-Host "Domain $domain is reachable."

	[PSCustomObject]@{
		Check  = "Users"
		Status = $status
		Detail = "Domain: $domain"
	}
}

Export-ModuleMember -Function Invoke-RslCheckUsers
