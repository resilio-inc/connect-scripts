function Get-DomainJoinResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedDomain,
        [ref]$IsDomainReady,
        [ref]$ActualDomain
    )

    $IsDomainReady.Value = $false
    $ActualDomain.Value = $null

    try
    {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

        if (-not $computerSystem.PartOfDomain)
        {
            return @(
                [PSCustomObject]@{
                    Check  = "AD.DomainJoined"
                    Status = "FAIL"
                    Detail = "Machine is not joined to a domain."
                }
            )
        }

        $ActualDomain.Value = [string]$computerSystem.Domain
        if (-not [string]::IsNullOrWhiteSpace($ExpectedDomain) -and $ActualDomain.Value -ne $ExpectedDomain)
        {
            return @(
                [PSCustomObject]@{
                    Check  = "AD.DomainJoined"
                    Status = "FAIL"
                    Detail = "Machine is joined to '$($ActualDomain.Value)', expected '$ExpectedDomain'."
                }
            )
        }

        $IsDomainReady.Value = $true
        return @(
            [PSCustomObject]@{
                Check  = "AD.DomainJoined"
                Status = "PASS"
                Detail = "Machine is domain-joined: $($ActualDomain.Value)"
            }
        )
    }
    catch
    {
        return @(
            [PSCustomObject]@{
                Check  = "AD.DomainJoined"
                Status = "FAIL"
                Detail = "Unable to determine domain join status: $($_.Exception.Message)"
            }
        )
    }
}

function Get-AdToolsAvailabilityResult {
    param(
        [ref]$IsAvailable
    )

    $IsAvailable.Value = $false

    if (-not (Get-Command Get-ADComputer -ErrorAction SilentlyContinue))
    {
        return @(
            [PSCustomObject]@{
                Check  = "AD.Tools"
                Status = "FAIL"
                Detail = "Get-ADComputer is not available. Install RSAT Active Directory PowerShell tools."
            }
        )
    }

    $IsAvailable.Value = $true
    return @(
        [PSCustomObject]@{
            Check  = "AD.Tools"
            Status = "PASS"
            Detail = "Active Directory PowerShell tools are available."
        }
    )
}

function Get-ExpectedSpns {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [ref]$ExpectedSpns
    )

    $ExpectedSpns.Value = @(
        $Config.SPNs |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { ([string]$_).Trim() }
    )

    if ($ExpectedSpns.Value.Count -eq 0)
    {
        return @(
            [PSCustomObject]@{
                Check  = "AD.SPN.Config"
                Status = "WARNING"
                Detail = "No SPNs configured in config file; SPN validation was skipped."
            }
        )
    }

    return @(
        [PSCustomObject]@{
            Check  = "AD.SPN.Config"
            Status = "PASS"
            Detail = "Configured SPNs count: $($ExpectedSpns.Value.Count)"
        }
    )
}

function Get-AssignedSpnsForLocalComputer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [ref]$AssignedSpns,
        [ref]$ReadSucceeded
    )

    $ReadSucceeded.Value = $false
    $AssignedSpns.Value = @()

    try
    {
        $adComputer = Get-ADComputer `
            -Identity $ComputerName `
            -Properties ServicePrincipalName `
            -ErrorAction Stop

        $AssignedSpns.Value = @(
            $adComputer.ServicePrincipalName |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim() }
        )

        $ReadSucceeded.Value = $true
        return @(
            [PSCustomObject]@{
                Check  = "AD.SPN.Assigned"
                Status = "PASS"
                Detail = "Assigned SPNs on '$ComputerName': $($AssignedSpns.Value.Count)"
            }
        )
    }
    catch
    {
        return @(
            [PSCustomObject]@{
                Check  = "AD.SPN.Assigned"
                Status = "FAIL"
                Detail = "Unable to read AD computer SPNs for '$ComputerName': $($_.Exception.Message)"
            }
        )
    }
}

function Get-SpnValidationResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedSpns,
        [Parameter(Mandatory = $true)]
        [string[]]$AssignedSpns
    )

    $assignedSpnSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($spn in $AssignedSpns)
    {
        [void]$assignedSpnSet.Add($spn)
    }

    $missingSpns = @(
        foreach ($spn in $ExpectedSpns)
        {
            if (-not $assignedSpnSet.Contains($spn))
            {
                $spn
            }
        }
    )

    if ($missingSpns.Count -eq 0)
    {
        return @(
            [PSCustomObject]@{
                Check  = "AD.SPN"
                Status = "PASS"
                Detail = "All configured SPNs are assigned to '$ComputerName'."
            }
        )
    }

    return @(
        [PSCustomObject]@{
            Check  = "AD.SPN"
            Status = "FAIL"
            Detail = "Missing SPNs on '$ComputerName': $($missingSpns -join ', ')"
        }
    )
}

function Invoke-RslCheckAD
{
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    Write-Host "Checking Active Directory..."

    $results = @()
    $computerName = $env:COMPUTERNAME
    $expectedDomain = [string]$Config.Domain

    $adToolsAvailable = $false
    $results += Get-AdToolsAvailabilityResult -IsAvailable ([ref]$adToolsAvailable)

    if (-not $adToolsAvailable)
    {
        return $results
    }

    $isDomainReady = $false
    $actualDomain = $null
    $results += Get-DomainJoinResult `
        -ExpectedDomain $expectedDomain `
        -IsDomainReady ([ref]$isDomainReady) `
        -ActualDomain ([ref]$actualDomain)

    if (-not $isDomainReady)
    {
        return $results
    }

    $expectedSpns = @()
    $results += Get-ExpectedSpns -Config $Config -ExpectedSpns ([ref]$expectedSpns)

    if ($expectedSpns.Count -eq 0)
    {
        return $results
    }

    $assignedSpns = @()
    $spnReadSucceeded = $false
    $results += Get-AssignedSpnsForLocalComputer `
        -ComputerName $computerName `
        -AssignedSpns ([ref]$assignedSpns) `
        -ReadSucceeded ([ref]$spnReadSucceeded)

    if (-not $spnReadSucceeded)
    {
        return $results
    }

    $results += Get-SpnValidationResult `
        -ComputerName $computerName `
        -ExpectedSpns $expectedSpns `
        -AssignedSpns $assignedSpns

    $results
}

Export-ModuleMember -Function Invoke-RslCheckAD
