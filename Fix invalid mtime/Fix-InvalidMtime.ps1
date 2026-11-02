<#
.SYNOPSIS
Fixes invalid mtime only for the files Resilio Connect reports with SE_FS_INVALID_MODIFICATION_TIME, without a recursive folder scan.

.DESCRIPTION
The script runs ON the affected agent machine. It asks the Management Console API which files this agent
reported with an invalid modification time error, and sets their mtime to the current time.
Unlike fix-mtime.ps1 it does not walk the whole folder tree, so it is fast on large jobs.

Steps:
1. Finds this agent in the Management Console (by -AgentId, or by -AgentName, default is the computer name)
2. Reads the agent's current errors and picks the ones matching -ErrorCodes
3. For every such error gets the list of affected files (GET /runs/{run}/agents/{agent}/errors/files)
4. Sets LastWriteTime to now for each file that exists on disk

.PARAMETER McUrl
Management Console address, e.g. https://mc.example.local:8446. Default is the RESILIO_MC_URL environment variable.

.PARAMETER Token
Management Console API token. Default is the RESILIO_API_TOKEN environment variable. Do not hardcode it in the script.

.PARAMETER AgentName
Agent name as shown in the Management Console. Default is the computer name. Compared case-insensitively.

.PARAMETER AgentId
Agent ID in the Management Console. If set, -AgentName is ignored. Use it when the agent name in the console differs from the computer name.

.PARAMETER ErrorCodes
Error codes to process. Default: SE_FS_INVALID_MODIFICATION_TIME.

.PARAMETER MaxEntries
Maximum number of files to request per error. Default: 10000.

.PARAMETER WhatIf
Only show which files would be updated, don't change anything. API requests are still made (read-only).

.EXAMPLE
$env:RESILIO_MC_URL = "https://192.168.128.103:8446"
$env:RESILIO_API_TOKEN = "<token>"
.\Fix-InvalidMtime.ps1 -WhatIf
Dry run: shows which files would be fixed on this agent.

.EXAMPLE
.\Fix-InvalidMtime.ps1 -McUrl https://192.168.128.103:8446 -Token <token> -AgentId 6 *> log.txt
Fixes files for agent with id 6 and writes the output to log.txt.

.NOTES
TLS certificate of the Management Console is not verified (curl -k), as the console usually uses a self-signed certificate.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$McUrl        = $env:RESILIO_MC_URL,
    [string]$Token        = $env:RESILIO_API_TOKEN,
    [string]$AgentName    = $env:COMPUTERNAME,
    [int]$AgentId         = 0,
    [string[]]$ErrorCodes = @("SE_FS_INVALID_MODIFICATION_TIME"),
    [int]$MaxEntries      = 10000
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Invoke-ResilioAPI {
    param([string]$Endpoint)
    $url = "$script:ApiBase$Endpoint"
    $raw = curl.exe -s -k -w "`n%{http_code}" -H "Authorization: Token $Token" -H "Content-Type: application/json" $url
    if ($LASTEXITCODE -ne 0) {
        throw "Request to $url failed (curl exit code $LASTEXITCODE). Check McUrl and network access."
    }
    $lines = @($raw)
    $httpCode = $lines[-1]
    $body = ($lines[0..($lines.Count - 2)] -join "`n")
    if ($httpCode -notmatch '^2') {
        throw "GET $Endpoint returned HTTP $httpCode. Response: $body"
    }
    try {
        return $body | ConvertFrom-Json
    } catch {
        throw "GET $Endpoint returned a response that is not JSON: $body"
    }
}

# ------------------------------------------------------------
Write-Host "Script version 1.1 (2026-11-02) started"

if (-not $McUrl) { throw "Management Console address is not set. Use -McUrl or the RESILIO_MC_URL environment variable." }
if (-not $Token) { throw "API token is not set. Use -Token or the RESILIO_API_TOKEN environment variable." }
$script:ApiBase = "$($McUrl.TrimEnd('/'))/api/v2"

# ------------------------------------------------------------
# 1. Find this agent
# ------------------------------------------------------------
if ($AgentId -gt 0) {
    Write-Log "Using agent id $AgentId" "Cyan"
    $agentDetails = Invoke-ResilioAPI -Endpoint "/agents/$AgentId"
} else {
    Write-Log "Looking up agent '$AgentName'..." "Cyan"
    $agents = @(Invoke-ResilioAPI -Endpoint "/agents")
    $agent = $agents | Where-Object { $_.name -ieq $AgentName } | Select-Object -First 1

    if (-not $agent) {
        if ($agents.Count -eq 0) {
            Write-Log "Management Console returned no agents. Check that the token has access to agents." "Red"
        } else {
            Write-Log "Agent '$AgentName' not found. Agents in the Management Console:" "Red"
            $agents | ForEach-Object { Write-Log "  - $($_.name) (id: $($_.id))" }
            Write-Log "Run again with -AgentName '<name>' or -AgentId <id>." "Yellow"
        }
        exit 1
    }
    $AgentId = $agent.id
    Write-Log "Agent id: $AgentId" "Green"
    $agentDetails = Invoke-ResilioAPI -Endpoint "/agents/$AgentId"
}

# ------------------------------------------------------------
# 2. Pick matching errors
# ------------------------------------------------------------
$relevantErrors = @($agentDetails.errors | Where-Object { $ErrorCodes -contains $_.code_str })

if ($relevantErrors.Count -eq 0) {
    Write-Log "No errors matching [$($ErrorCodes -join ', ')] found for this agent. Nothing to fix." "Green"
    exit 0
}
Write-Log "Found $($relevantErrors.Count) matching error(s)." "Yellow"

# ------------------------------------------------------------
# 3. Get affected files for each error and fix them
# ------------------------------------------------------------
$totalAffected = 0
$totalFixed    = 0
$totalFailed   = 0
$totalSkipped  = 0

foreach ($err in $relevantErrors) {
    Write-Log "Error: $($err.code_str) | job_id=$($err.job_id) job_run_id=$($err.job_run_id)" "Cyan"
    Write-Log "  $($err.message)"

    $endpoint = "/runs/$($err.job_run_id)/agents/$AgentId/errors/files" +
                "?folderid=$($err.folderid)&error_code=$($err.code_str)&max_entries=$MaxEntries"
    $filesResult = Invoke-ResilioAPI -Endpoint $endpoint

    if (-not $filesResult.files -or @($filesResult.files).Count -eq 0) {
        Write-Log "  No file details returned for this error." "Yellow"
        continue
    }

    Write-Log "  Base path: $($filesResult.path)"
    Write-Log "  Affected files: $($filesResult.size)"
    $totalAffected += $filesResult.size

    foreach ($f in $filesResult.files) {
        # files[].path is relative to the base path; some error types return plain strings instead of objects
        $relPath = if ($f -is [string]) { $f } elseif ($f.path) { $f.path } else { $null }
        if (-not $relPath) {
            Write-Log "    [SKIP] Could not determine path for entry: $($f | ConvertTo-Json -Compress)" "DarkYellow"
            $totalSkipped++
            continue
        }

        $fullPath = Join-Path $filesResult.path $relPath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            Write-Log "    [SKIP] Not found on disk: $fullPath" "DarkYellow"
            $totalSkipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess($fullPath, "Set LastWriteTime to now")) {
            try {
                [System.IO.File]::SetLastWriteTime($fullPath, (Get-Date))
                Write-Log "    [FIXED] $fullPath" "Green"
                $totalFixed++
            } catch {
                Write-Log "    [FAILED] $fullPath : $($_.Exception.Message)" "Red"
                $totalFailed++
            }
        }
    }
}

Write-Log "=== Summary ===" "Cyan"
Write-Log "Total affected (reported by API): $totalAffected"
Write-Log "Fixed: $totalFixed" "Green"
if ($totalSkipped -gt 0) { Write-Log "Skipped: $totalSkipped" "DarkYellow" }
if ($totalFailed -gt 0) { Write-Log "Failed: $totalFailed" "Red" }
if ($WhatIfPreference) { Write-Log "(ran with -WhatIf, no files were actually changed)" "Yellow" }
