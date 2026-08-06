#Requires -Version 5.1
<#
.SYNOPSIS
    Resilio Connect — Unicode Filename Fixer (PowerShell, pure, no Python)

.DESCRIPTION
    Designed to run as a Resilio Connect Script Running Job on Windows agents.

    Queries the Management Console API v2, finds all active job runs with
    SE_FS_INVALID_UNICODE_IN_FILE_NAME errors, scans the affected directories
    and renames files and directories whose names contain invalid UTF-16
    characters (unpaired surrogates U+D800-U+DFFF), replacing them with "_".

    Compatible with PowerShell 5.1 and PowerShell 7+.

    PARAMETERS (via Agent Tags in MC or environment variables):
      TAG_MC_URL      Management Console URL, e.g. https://192.168.1.1:8446
      TAG_API_TOKEN   API token (MC -> Settings -> API -> Generate Token)
      TAG_APPLY       "true" to rename files, anything else = dry-run
      TAG_LOG_DIR     Directory for log files (optional, default: %TEMP%)

    LOG FILE:
      resilio_fix_unicode_YYYYMMDD_HHmmss.log
      Written to TAG_LOG_DIR or %TEMP% if not set.

.NOTES
    Rename engine uses Win32 MoveFileW via P/Invoke to handle surrogate
    codepoints that PowerShell Rename-Item cannot process.
#>

# ── PowerShell version check ──────────────────────────────────────────────────

$psVersion = $PSVersionTable.PSVersion
$psMajor   = $psVersion.Major
$psMinor   = $psVersion.Minor

if ($psMajor -lt 5 -or ($psMajor -eq 5 -and $psMinor -lt 1)) {
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Red
    Write-Host "  ERROR: PowerShell 5.1 or higher is required." -ForegroundColor Red
    Write-Host "  Current version: $psVersion" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "  Your Windows version and recommended action:" -ForegroundColor Yellow
    Write-Host ""

    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -eq 6 -and $osVersion.Minor -eq 1) {
        # Windows 7 / Server 2008 R2
        Write-Host "  Detected: Windows 7 / Server 2008 R2" -ForegroundColor Yellow
        Write-Host "  Install WMF 5.1:" -ForegroundColor Yellow
        Write-Host "  https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Cyan
    } elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -eq 2) {
        # Windows 8 / Server 2012
        Write-Host "  Detected: Windows 8 / Server 2012" -ForegroundColor Yellow
        Write-Host "  Install WMF 5.1:" -ForegroundColor Yellow
        Write-Host "  https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Cyan
    } elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -eq 3) {
        # Windows 8.1 / Server 2012 R2
        Write-Host "  Detected: Windows 8.1 / Server 2012 R2" -ForegroundColor Yellow
        Write-Host "  Install WMF 5.1:" -ForegroundColor Yellow
        Write-Host "  https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Cyan
    } else {
        Write-Host "  Install WMF 5.1:" -ForegroundColor Yellow
        Write-Host "  https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Or install PowerShell 7:" -ForegroundColor Yellow
        Write-Host "  https://github.com/PowerShell/PowerShell/releases/latest" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "  NOTE: Windows Server 2012 / 2012 R2 reached End of Life" -ForegroundColor Yellow
    Write-Host "        in October 2023. Consider upgrading your OS." -ForegroundColor Yellow
    Write-Host "=" * 70 -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ── Parameters from Agent Tags ────────────────────────────────────────────────

$MC_URL  = $env:TAG_MC_URL
$TOKEN   = $env:TAG_API_TOKEN
$APPLY   = ($env:TAG_APPLY -eq "true")
$LOG_DIR = if ($env:TAG_LOG_DIR) { $env:TAG_LOG_DIR } else { $env:TEMP }

# ── Validate required parameters ──────────────────────────────────────────────

if (-not $MC_URL) {
    Write-Host "ERROR: TAG_MC_URL is not set. Set it as an Agent Tag in MC." -ForegroundColor Red
    exit 1
}
if (-not $TOKEN) {
    Write-Host "ERROR: TAG_API_TOKEN is not set. Set it as an Agent Tag in MC." -ForegroundColor Red
    exit 1
}

# ── Constants ─────────────────────────────────────────────────────────────────

$TARGET_ERROR_CODE = "SE_FS_INVALID_UNICODE_IN_FILE_NAME"
$API_BASE          = "$MC_URL/api/v2"
$MAX_ENTRIES       = 10000
$REPLACEMENT_CHAR  = "_"
$SCRIPT_START_TIME = Get-Date


# ── Log setup ─────────────────────────────────────────────────────────────────

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

$ts      = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LOG_DIR "resilio_fix_unicode_$ts.log"

$logWriter = [System.IO.StreamWriter]::new(
    $LogFile,
    $false,
    [System.Text.UTF8Encoding]::new($false)  # UTF-8, no BOM
)
$logWriter.AutoFlush = $true

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line      = "$timestamp  $($Level.PadRight(7))  $Message"
    $logWriter.WriteLine($line)
    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line }
    }
}

function Write-LogSeparator { Write-Log ("=" * 70) }
function Write-LogBlank     { Write-Log "" }

function Close-Log {
    $logWriter.Flush()
    $logWriter.Close()
    $logWriter.Dispose()
}


# ── SSL: ignore self-signed certificate ───────────────────────────────────────

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
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}


# ── Win32 MoveFileW via P/Invoke ──────────────────────────────────────────────

if (-not ([System.Management.Automation.PSTypeName]'Win32MoveFile').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32MoveFile {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool MoveFileW(string lpExistingFileName, string lpNewFileName);

    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
}
"@
}

# Win32 error code descriptions for the most common rename failures
$WIN32_ERRORS = @{
    2   = "File not found"
    3   = "Path not found"
    5   = "Access denied"
    17  = "Not the same device"
    32  = "File is in use by another process"
    80  = "File already exists"
    183 = "File already exists (duplicate name)"
    206 = "Filename too long"
}

function Get-Win32ErrorDescription([uint32]$Code) {
    if ($WIN32_ERRORS.ContainsKey([int]$Code)) {
        return "$Code ($($WIN32_ERRORS[[int]$Code]))"
    }
    return "$Code"
}


# ── Surrogate detection & name sanitization ───────────────────────────────────

function Test-HasSurrogate {
    param([string]$Name)
    foreach ($ch in $Name.ToCharArray()) {
        $cp = [int][char]$ch
        if ($cp -ge 0xD800 -and $cp -le 0xDFFF) { return $true }
    }
    return $false
}

function Get-SurrogatePositions {
    param([string]$Name)
    $positions = @()
    $chars = $Name.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $cp = [int][char]$chars[$i]
        if ($cp -ge 0xD800 -and $cp -le 0xDFFF) {
            $positions += "pos=$i U+$('{0:X4}' -f $cp)"
        }
    }
    return $positions
}

function Get-SanitizedName {
    param([string]$Name)
    $ext  = [System.IO.Path]::GetExtension($Name)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)

    $chars              = $base.ToCharArray()
    $result             = [System.Text.StringBuilder]::new()
    $lastWasReplacement = $false

    foreach ($ch in $chars) {
        $cp = [int][char]$ch
        if ($cp -ge 0xD800 -and $cp -le 0xDFFF) {
            if (-not $lastWasReplacement) {
                [void]$result.Append($REPLACEMENT_CHAR)
                $lastWasReplacement = $true
            }
        } else {
            [void]$result.Append($ch)
            $lastWasReplacement = $false
        }
    }

    $sanitized = $result.ToString().Trim($REPLACEMENT_CHAR)
    if (-not $sanitized) { $sanitized = "renamed" }
    return $sanitized + $ext
}

function Get-UniquePath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir  = Split-Path $Path -Parent
    $ext  = [System.IO.Path]::GetExtension($Path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $i    = 1
    do {
        $candidate = Join-Path $dir "$base`_$i$ext"
        $i++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}


# ── Rename log entries ────────────────────────────────────────────────────────

# Collect all rename operations for the final summary block
$renameLog = [System.Collections.Generic.List[string]]::new()

function Invoke-Rename {
    param(
        [string]$OldPath,
        [string]$NewPath,
        [bool]$IsDir,
        [bool]$Apply,
        [string[]]$SurrogateInfo
    )
    $oldName  = Split-Path $OldPath -Leaf
    $newName  = Split-Path $NewPath -Leaf
    $dir      = Split-Path $OldPath -Parent
    $typeTag  = if ($IsDir) { "[DIR]  " } else { "[FILE] " }
    $surInfo  = if ($SurrogateInfo) { " surrogates: $($SurrogateInfo -join ', ')" } else { "" }

    if ($Apply) {
        $ok = [Win32MoveFile]::MoveFileW($OldPath, $NewPath)
        if ($ok) {
            $msg = "$typeTag[RENAMED]  from: '$oldName'  ->  to: '$newName'  dir: '$dir'$surInfo"
            Write-Log $msg "SUCCESS"
            $renameLog.Add($msg)
            return $true
        } else {
            $errCode = [Win32MoveFile]::GetLastError()
            $errDesc = Get-Win32ErrorDescription $errCode
            $msg = "$typeTag[ERROR]    from: '$oldName'  win32_error: $errDesc  dir: '$dir'"
            Write-Log $msg "ERROR"
            $renameLog.Add($msg)
            return $false
        }
    } else {
        $msg = "$typeTag[DRY-RUN]  from: '$oldName'  ->  to: '$newName'  dir: '$dir'$surInfo"
        Write-Log $msg
        $renameLog.Add($msg)
        return $true
    }
}


# ── Directory scanner & fixer ─────────────────────────────────────────────────

function Repair-Directory {
    param(
        [string]$RootPath,
        [bool]$Apply
    )

    $stats = @{
        Scanned     = 0
        Clean       = 0
        Renamed     = 0
        Errors      = 0
        DirsFixed   = 0
        FilesFixed  = 0
    }

    # Collect all entries using System.IO which handles surrogate names
    $allEntries = [System.Collections.Generic.List[object]]::new()

    function Collect-Entries([string]$Dir) {
        try {
            $entries = [System.IO.Directory]::GetFileSystemEntries($Dir)
            foreach ($entry in $entries) {
                $isDir = [System.IO.Directory]::Exists($entry)
                $allEntries.Add([PSCustomObject]@{
                    Path  = $entry
                    IsDir = $isDir
                    Depth = ($entry.Split([System.IO.Path]::DirectorySeparatorChar)).Count
                })
                if ($isDir) { Collect-Entries $entry }
            }
        } catch {
            Write-Log "WARNING: cannot enumerate '$Dir': $_" "WARNING"
        }
    }

    Write-Log "  Collecting entries..."
    Collect-Entries $RootPath
    Write-Log "  Found $($allEntries.Count) entries total"

    # Sort deepest first — children before parents (bottom-up)
    $sorted = $allEntries | Sort-Object { $_.Depth } -Descending

    foreach ($entry in $sorted) {
        $name = Split-Path $entry.Path -Leaf
        $stats.Scanned++

        if (-not (Test-HasSurrogate $name)) {
            Write-Log "  [OK]     '$name'" 
            $stats.Clean++
            continue
        }

        # Get surrogate details for log
        $surrogates = Get-SurrogatePositions $name
        $newName    = Get-SanitizedName $name
        $newPath    = Join-Path (Split-Path $entry.Path -Parent) $newName
        $newPath    = Get-UniquePath $newPath

        $ok = Invoke-Rename `
            -OldPath      $entry.Path `
            -NewPath      $newPath `
            -IsDir        $entry.IsDir `
            -Apply        $Apply `
            -SurrogateInfo $surrogates

        if ($ok) {
            $stats.Renamed++
            if ($entry.IsDir) { $stats.DirsFixed++ } else { $stats.FilesFixed++ }
        } else {
            $stats.Errors++
        }
    }

    return $stats
}


# ── API helpers ───────────────────────────────────────────────────────────────

function Invoke-McApi {
    param([string]$Path)
    $url     = "$API_BASE$Path"
    $headers = @{ Authorization = "Token $TOKEN" }
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            return Invoke-RestMethod -Uri $url -Headers $headers `
                                     -SkipCertificateCheck -TimeoutSec 30
        } else {
            return Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30
        }
    } catch {
        throw "API error [$url]: $_"
    }
}

function Get-AllRuns {
    $limit  = 100
    $offset = 0
    $result = [System.Collections.Generic.List[object]]::new()
    do {
        $data  = Invoke-McApi "/runs?limit=$limit&offset=$offset"
        $items = if ($data.data) { $data.data } else { @($data) }
        foreach ($item in $items) { $result.Add($item) }
        $total  = if ($data.total) { [int]$data.total } else { $items.Count }
        $offset += $items.Count
    } while ($offset -lt $total -and $items.Count -gt 0)
    return $result
}

function Get-ErrorFiles {
    param([int]$RunId, [int]$AgentId, [string]$FolderId)
    return Invoke-McApi "/runs/$RunId/agents/$AgentId/errors/files?error_code=$TARGET_ERROR_CODE&folderid=$FolderId&max_entries=$MAX_ENTRIES"
}

function Get-DirsToScan {
    param([string]$BasePath, [array]$ApiFiles)
    $dirs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($f in $ApiFiles) {
        $rel    = if ($f.path) { $f.path } else { $f.name }
        $relDir = Split-Path $rel -Parent
        while ($relDir -and $relDir.Contains([char]0xFFFD)) {
            $relDir = Split-Path $relDir -Parent
        }
        $full = if ($relDir -and -not $relDir.Contains([char]0xFFFD)) {
            Join-Path $BasePath $relDir
        } else {
            $BasePath
        }
        [void]$dirs.Add($full)
    }
    if ($dirs.Count -eq 0) { return @($BasePath) }
    return @($dirs | Sort-Object)
}


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

# ── Header ────────────────────────────────────────────────────────────────────

Write-LogSeparator
Write-Log "  resilio_fix_unicode_scriptjob.ps1"
Write-Log "  Started   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "  Agent     : $env:COMPUTERNAME"
Write-Log "  User      : $env:USERNAME"
Write-Log "  PS Version: $($PSVersionTable.PSVersion)"
Write-Log "  OS        : $([System.Environment]::OSVersion.VersionString)"
Write-Log "  MC URL    : $MC_URL"
Write-Log "  Mode      : $(if ($APPLY) { 'APPLY — files WILL be renamed' } else { 'DRY-RUN — no changes will be made' })"
Write-Log "  Log file  : $LogFile"
Write-LogSeparator

if (-not $APPLY) {
    Write-Log "  *** DRY-RUN MODE — no files will be changed ***"
    Write-Log "  *** Set TAG_APPLY=true to perform the renames ***"
    Write-LogSeparator
}

# ── Fetch runs ────────────────────────────────────────────────────────────────

Write-LogBlank
Write-Log "[*] Querying MC API: $API_BASE/runs"

try {
    $runs = Get-AllRuns
} catch {
    Write-Log "FATAL: cannot connect to MC API: $_" "ERROR"
    Close-Log
    exit 1
}

Write-Log "    Total runs found: $($runs.Count)"

# ── Find unicode errors ───────────────────────────────────────────────────────

$allDirs = [System.Collections.Generic.List[string]]::new()
$seen    = [System.Collections.Generic.HashSet[string]]::new()
$jobsWithErrors = 0

foreach ($run in $runs) {
    $unicodeErrors = @($run.errors | Where-Object { $_.code_str -eq $TARGET_ERROR_CODE })
    if ($unicodeErrors.Count -eq 0) { continue }

    $jobsWithErrors++
    $runId   = $run.id
    $runName = if ($run.name) { $run.name } else { "run#$runId" }

    Write-LogBlank
    Write-Log "[!] Run '$runName' (id=$runId, job_id=$($run.job_id)) — $($unicodeErrors.Count) Unicode error(s)"
    Write-Log "    Status : $($run.status)"
    Write-Log "    Type   : $($run.type)"

    foreach ($err in $unicodeErrors) {
        $agentId  = $err.agent_id
        $folderId = $err.folderid

        Write-LogBlank
        Write-Log "    [error] agent_id  = $agentId"
        Write-Log "    [error] folderid  = $folderId"
        Write-Log "    [error] message   = $($err.message)"
        Write-Log "    Fetching file list from API..."

        try {
            $resp = Get-ErrorFiles -RunId $runId -AgentId $agentId -FolderId $folderId
        } catch {
            Write-Log "    ERROR fetching files: $_" "ERROR"
            continue
        }

        $basePath = $resp.path
        $apiFiles = @($resp.files)
        $size     = if ($resp.size) { $resp.size } else { $apiFiles.Count }

        Write-Log "    Base path      : $basePath"
        Write-Log "    Files affected : $size"
        foreach ($f in $apiFiles) {
            $fname = if ($f.path) { $f.path } else { $f.name }
            Write-Log "      - $fname"
        }

        if (-not $basePath) {
            Write-Log "    SKIP: base_path is empty" "WARNING"
            continue
        }

        # Check if this path exists on THIS agent
        if (-not (Test-Path -LiteralPath $basePath)) {
            Write-Log "    SKIP: path '$basePath' does not exist on this agent ($env:COMPUTERNAME)" "WARNING"
            continue
        }

        $dirs = Get-DirsToScan -BasePath $basePath -ApiFiles $apiFiles
        Write-Log "    Dirs to scan   : $($dirs -join ', ')"

        foreach ($d in $dirs) {
            if ($seen.Add($d)) { $allDirs.Add($d) }
        }
    }
}

Write-LogBlank

if ($jobsWithErrors -eq 0) {
    Write-Log "No $TARGET_ERROR_CODE errors found in any run. All clean!" "SUCCESS"
    Write-LogBlank
    Write-Log "Finished in $([math]::Round(((Get-Date) - $SCRIPT_START_TIME).TotalSeconds, 1))s"
    Close-Log
    exit 0
}

if ($allDirs.Count -eq 0) {
    Write-Log "Errors found in MC but no matching paths on this agent ($env:COMPUTERNAME)." "WARNING"
    Write-Log "The errors may belong to a different agent."
    Close-Log
    exit 0
}

Write-LogSeparator
Write-Log "Unique directories to process: $($allDirs.Count)"
foreach ($d in $allDirs) { Write-Log "  $d" }
Write-LogSeparator

# ── Process directories ───────────────────────────────────────────────────────

$grandTotal = @{
    Scanned    = 0
    Clean      = 0
    Renamed    = 0
    Errors     = 0
    DirsFixed  = 0
    FilesFixed = 0
}

foreach ($dir in $allDirs) {
    Write-LogBlank
    Write-LogSeparator
    Write-Log "Processing: $dir"
    Write-LogSeparator

    $stats = Repair-Directory -RootPath $dir -Apply $APPLY

    $grandTotal.Scanned    += $stats.Scanned
    $grandTotal.Clean      += $stats.Clean
    $grandTotal.Renamed    += $stats.Renamed
    $grandTotal.Errors     += $stats.Errors
    $grandTotal.DirsFixed  += $stats.DirsFixed
    $grandTotal.FilesFixed += $stats.FilesFixed

    Write-LogBlank
    Write-Log "  Directory result:"
    Write-Log "    Scanned  : $($stats.Scanned)"
    Write-Log "    Clean    : $($stats.Clean)"
    Write-Log "    Renamed  : $($stats.Renamed) (dirs: $($stats.DirsFixed), files: $($stats.FilesFixed))"
    Write-Log "    Errors   : $($stats.Errors)"
}

# ── Rename summary block ──────────────────────────────────────────────────────

if ($renameLog.Count -gt 0) {
    Write-LogBlank
    Write-LogSeparator
    Write-Log "ALL RENAME OPERATIONS ($($renameLog.Count) total):"
    Write-LogSeparator
    foreach ($entry in $renameLog) {
        Write-Log $entry
    }
}

# ── Final summary ─────────────────────────────────────────────────────────────

$elapsed = [math]::Round(((Get-Date) - $SCRIPT_START_TIME).TotalSeconds, 1)

Write-LogBlank
Write-LogSeparator
Write-Log "FINAL SUMMARY"
Write-LogSeparator
Write-Log "Finished   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Duration   : ${elapsed}s"
Write-Log "Agent      : $env:COMPUTERNAME"
Write-Log "Mode       : $(if ($APPLY) { 'APPLY' } else { 'DRY-RUN' })"
Write-LogBlank
Write-Log "Dirs processed : $($allDirs.Count)"
Write-Log "Entries scanned: $($grandTotal.Scanned)"
Write-Log "  Clean (OK)   : $($grandTotal.Clean)"
Write-Log "  Renamed      : $($grandTotal.Renamed)"
Write-Log "    Directories: $($grandTotal.DirsFixed)"
Write-Log "    Files      : $($grandTotal.FilesFixed)"
if ($grandTotal.Errors -gt 0) {
    Write-Log "  Errors       : $($grandTotal.Errors)" "ERROR"
} else {
    Write-Log "  Errors       : 0"
}
Write-LogBlank
if (-not $APPLY) {
    Write-Log "DRY-RUN complete. Set TAG_APPLY=true to apply renames." "WARNING"
} else {
    if ($grandTotal.Renamed -gt 0) {
        Write-Log "Done. Resilio will re-scan the folders automatically." "SUCCESS"
    } else {
        Write-Log "Done. No files needed renaming." "SUCCESS"
    }
}
Write-LogBlank
Write-Log "Log saved to: $LogFile"
Write-LogSeparator

Close-Log

if ($grandTotal.Errors -gt 0) { exit 1 } else { exit 0 }
