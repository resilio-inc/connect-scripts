<#
.SYNOPSIS
    Resilio Connect Unicode Filename Fixer - PowerShell Wrapper

.DESCRIPTION
    Queries the Resilio Connect Management Console API v2, finds all active
    job runs with SE_FS_INVALID_UNICODE_IN_FILE_NAME errors, and invokes
    fix_non_utf8_names.py (Python engine) to rename files and directories
    whose names contain invalid UTF-16 surrogates or legacy-encoded bytes.

    This script is a wrapper ("candy wrapper") around the Python engine:
        fix_non_utf8_names.py  <-- actual rename logic lives here

    Both files must be in the same directory:
        resilio_fix_unicode_wrapper.ps1   <-- this file
        fix_non_utf8_names.py             <-- Python engine

.PARAMETER McUrl
    Management Console URL, e.g. https://192.168.1.1:8446

.PARAMETER Token
    API token (MC -> Settings -> API)

.PARAMETER Apply
    Actually rename files. Default is dry-run (show plan only).

.PARAMETER LogFile
    Path to the .log file. Default: auto-generated next to this script.
    resilio_fix_unicode_YYYYMMDD_HHmmss.log

.PARAMETER Encodings
    Comma-separated list of candidate encodings passed to the Python engine.
    Default: cp1251,cp866,koi8-r,mac_cyrillic,cp1252

.EXAMPLE
    # Dry-run
    .\resilio_fix_unicode_wrapper.ps1 -McUrl https://192.168.128.103:8446 -Token YOUR_TOKEN

.EXAMPLE
    # Apply renames
    .\resilio_fix_unicode_wrapper.ps1 -McUrl https://192.168.128.103:8446 -Token YOUR_TOKEN -Apply

.EXAMPLE
    # Apply with custom log path
    .\resilio_fix_unicode_wrapper.ps1 -McUrl https://192.168.128.103:8446 -Token YOUR_TOKEN -Apply -LogFile C:\Logs\fix.log
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$McUrl,

    [Parameter(Mandatory = $true)]
    [string]$Token,

    [switch]$Apply,

    [string]$LogFile = "",

    [string]$Encodings = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force UTF-8 output so Cyrillic and replacement chars display correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONUTF8 = "1"

# ── Constants ─────────────────────────────────────────────────────────────────

$TARGET_ERROR_CODE = "SE_FS_INVALID_UNICODE_IN_FILE_NAME"
$API_BASE          = "$McUrl/api/v2"
$SCRIPT_DIR        = $PSScriptRoot
$PYTHON_ENGINE     = Join-Path $SCRIPT_DIR "fix_non_utf8_names.py"


# ── Log setup ─────────────────────────────────────────────────────────────────

if ($LogFile -eq "") {
    $ts      = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $SCRIPT_DIR "resilio_fix_unicode_$ts.log"
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts  $($Level.PadRight(7))  $Message"
    # Write to console
    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        default   { Write-Host $line }
    }
    # Append to log file (UTF-8 no BOM)
    $line | Out-File -FilePath $LogFile -Append -Encoding utf8NoBOM
}


# ── SSL: ignore self-signed cert on MC ────────────────────────────────────────

# PowerShell 7+ supports -SkipCertificateCheck directly on Invoke-RestMethod.
# For PS 5.1 compatibility we also add the type override below.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCerts').Type) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint sp, X509Certificate cert,
        WebRequest req, int problem) { return true; }
}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
    }
}


# ── API helpers ───────────────────────────────────────────────────────────────

function Invoke-McApi {
    param([string]$Path)
    $url     = "$API_BASE$Path"
    $headers = @{ Authorization = "Token $Token" }
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            return Invoke-RestMethod -Uri $url -Headers $headers `
                                     -SkipCertificateCheck -TimeoutSec 30
        } else {
            return Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30
        }
    } catch {
        throw "API error for $url : $_"
    }
}


function Get-AllRuns {
    $limit  = 100
    $offset = 0
    $result = @()
    do {
        $data   = Invoke-McApi "/runs?limit=$limit&offset=$offset"
        $items  = if ($data.data) { $data.data } else { $data }
        $result += $items
        $total  = if ($data.total) { $data.total } else { $items.Count }
        $offset += $items.Count
    } while ($offset -lt $total -and $items.Count -gt 0)
    return $result
}


function Get-ErrorFiles {
    param([int]$RunId, [int]$AgentId, [string]$FolderId)
    $path = "/runs/$RunId/agents/$AgentId/errors/files" +
            "?error_code=$TARGET_ERROR_CODE&folderid=$FolderId&max_entries=10000"
    return Invoke-McApi $path
}


# ── Directory resolution (mirrors Python dirs_to_scan logic) ──────────────────

function Get-DirsToScan {
    param([string]$BasePath, [array]$ApiFiles)

    $dirs = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($f in $ApiFiles) {
        $rel    = if ($f.path) { $f.path } else { $f.name }
        $relDir = Split-Path $rel -Parent

        # Walk up while directory segment contains replacement char (U+FFFD)
        while ($relDir -and $relDir.Contains([char]0xFFFD)) {
            $relDir = Split-Path $relDir -Parent
        }

        if ($relDir -and -not $relDir.Contains([char]0xFFFD)) {
            $full = Join-Path $BasePath $relDir
        } else {
            $full = $BasePath
        }
        [void]$dirs.Add($full)
    }

    if ($dirs.Count -eq 0) { return @($BasePath) }
    return $dirs | Sort-Object
}


# ── Python engine check ───────────────────────────────────────────────────────

function Assert-PythonEngine {
    if (-not (Test-Path $PYTHON_ENGINE)) {
        Write-Log "Python engine not found: $PYTHON_ENGINE" "ERROR"
        Write-Log "Place fix_non_utf8_names.py in the same directory as this script." "ERROR"
        exit 1
    }
    # Check python is available
    try {
        $ver = & python --version 2>&1
        Write-Log "Python: $ver"
    } catch {
        Write-Log "Python not found in PATH. Install Python 3 and add it to PATH." "ERROR"
        exit 1
    }
}


# ── Invoke Python engine ──────────────────────────────────────────────────────

function Invoke-PythonEngine {
    param([string[]]$Dirs)

    $pyArgs = @($PYTHON_ENGINE) + $Dirs + @("--log", $LogFile)
    if ($Apply)     { $pyArgs += "--apply" }
    if ($Encodings) { $pyArgs += @("--encodings", $Encodings) }

    Write-Log ""
    Write-Log "[>] Running: python $($pyArgs -join ' ')"

    # Run Python engine and stream its stdout line by line to the console.
    # The engine writes to the shared log file directly via its FileHandler
    # (--log is passed above), so we only need to echo stdout to the console
    # here — no double-logging.
    $psi                        = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = "python"
    $psi.Arguments              = $pyArgs -join " "
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($psi)

    # Stream stdout line by line
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        Write-Host $line
    }

    # Print any stderr
    $errOut = $proc.StandardError.ReadToEnd()
    if ($errOut) {
        foreach ($line in $errOut -split "`n") {
            if ($line.Trim()) { Write-Host $line -ForegroundColor Red }
        }
    }

    $proc.WaitForExit()
    return $proc.ExitCode
}


# ── Main ──────────────────────────────────────────────────────────────────────

Write-Log ("=" * 60)
Write-Log "  resilio_fix_unicode_wrapper.ps1  started"
Write-Log "  MC URL : $McUrl"
Write-Log "  Mode   : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
Write-Log "  Log    : $LogFile"
Write-Log ("=" * 60)

if (-not $Apply) {
    Write-Log "  DRY-RUN MODE - no files will be changed"
    Write-Log "  Add -Apply to perform the renames"
    Write-Log ("=" * 60)
}

Assert-PythonEngine

# 1. Fetch all runs
Write-Log "[*] Fetching job runs..."
try {
    $runs = Get-AllRuns
} catch {
    Write-Log "API ERROR: $_" "ERROR"
    exit 1
}
Write-Log "    Runs found: $($runs.Count)"

# 2. Find runs with unicode errors
$tasks   = @()
$allDirs = [System.Collections.Generic.List[string]]::new()
$seen    = [System.Collections.Generic.HashSet[string]]::new()

foreach ($run in $runs) {
    $unicodeErrors = @($run.errors | Where-Object { $_.code_str -eq $TARGET_ERROR_CODE })
    if ($unicodeErrors.Count -eq 0) { continue }

    $runId   = $run.id
    $runName = if ($run.name) { $run.name } else { "run#$runId" }
    Write-Log ""
    Write-Log "[!] Run '$runName' (id=$runId) has $($unicodeErrors.Count) Unicode error(s)"

    foreach ($err in $unicodeErrors) {
        $agentId  = $err.agent_id
        $folderId = $err.folderid
        $msg      = $err.message

        Write-Log "    agent_id=$agentId folderid=$($folderId.Substring(0,16))..."
        Write-Log "    message: $msg"
        Write-Log "    Fetching affected file list..."

        try {
            $resp = Get-ErrorFiles -RunId $runId -AgentId $agentId -FolderId $folderId
        } catch {
            Write-Log "    ERROR fetching files: $_" "ERROR"
            continue
        }

        $basePath = $resp.path
        $apiFiles = @($resp.files)
        $size     = if ($resp.size) { $resp.size } else { $apiFiles.Count }

        Write-Log "    Base path:      $basePath"
        Write-Log "    Files affected: $size"
        foreach ($f in $apiFiles) {
            $name = if ($f.path) { $f.path } else { $f.name }
            Write-Log "      - $name"
        }

        if (-not $basePath) {
            Write-Log "    SKIP: base_path is empty" "WARNING"
            continue
        }

        $dirs = Get-DirsToScan -BasePath $basePath -ApiFiles $apiFiles
        Write-Log "    Directories to scan: $($dirs -join ', ')"

        foreach ($d in $dirs) {
            if ($seen.Add($d)) {
                $allDirs.Add($d)
            }
        }
    }
}

if ($allDirs.Count -eq 0) {
    Write-Log ""
    Write-Log "No $TARGET_ERROR_CODE errors found. All clean!"
    exit 0
}

Write-Log ""
Write-Log ("=" * 60)
Write-Log "Unique directories to fix: $($allDirs.Count)"
foreach ($d in $allDirs) { Write-Log "  $d" }
Write-Log ("=" * 60)

# 3. Call Python engine
$rc = Invoke-PythonEngine -Dirs $allDirs

Write-Log ""
if ($rc -eq 0) {
    if ($Apply) {
        Write-Log "Done. Resilio will re-scan the folders automatically."
    } else {
        Write-Log "Dry-run complete. Re-run with -Apply to apply renames."
    }
} else {
    Write-Log "fix_non_utf8_names.py exited with code $rc" "ERROR"
    exit $rc
}

Write-Log ""
Write-Log "Full log saved to: $LogFile"
