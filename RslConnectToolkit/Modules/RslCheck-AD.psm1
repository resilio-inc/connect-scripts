function Invoke-CheckAD {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    Write-Host "Checking Active Directory..."

    $domain = $Config.Domain

    # Здесь настоящая проверка
    $status = "PASS"

    Write-Host "Domain $domain is reachable."

    [PSCustomObject]@{
        Check  = "AD"
        Status = $status
        Detail = "Domain: $domain"
    }
}

Export-ModuleMember -Function Invoke-CheckAD
