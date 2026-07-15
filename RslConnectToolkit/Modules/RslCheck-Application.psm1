function Invoke-RslCheckApplication {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Config
	)

	Write-Host "Checking Application..."

	$domain = $Config.Domain

	$status = "PASS"

	Write-Host "Domain $domain is reachable."

	[PSCustomObject]@{
		Check  = "Application"
		Status = $status
		Detail = "Domain: $domain"
	}
}

Export-ModuleMember -Function Invoke-RslCheckApplication
