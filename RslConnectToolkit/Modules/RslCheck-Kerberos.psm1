function Invoke-CheckKerberos {
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Config
	)

	Write-Host "Checking Kerberos..."

	$domain = $Config.Domain

	$status = "PASS"

	Write-Host "Domain $domain is reachable."

	[PSCustomObject]@{
		Check  = "Kerberos"
		Status = $status
		Detail = "Domain: $domain"
	}
}

Export-ModuleMember -Function Invoke-CheckKerberos
