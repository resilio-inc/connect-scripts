# Build.ps1
# Builds a single distributable PowerShell script.

param(
	[switch]$Signup,
    [ValidateSet("Dev","Release")]
    $BuildType="Dev"
)

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseFolder = Join-Path $ProjectRoot "Release"
$OutputFile    = Join-Path $ReleaseFolder "RslConnectToolkit.ps1"

New-Item -ItemType Directory -Force -Path $ReleaseFolder | Out-Null
if (Test-Path $OutputFile)
{
    Remove-Item $OutputFile
}

function Get-RelativePathCompat
{
	param(
		[Parameter(Mandatory = $true)][string]$BasePath,
		[Parameter(Mandatory = $true)][string]$TargetPath
	)

	$baseResolved = [IO.Path]::GetFullPath($BasePath)
	$targetResolved = [IO.Path]::GetFullPath($TargetPath)

	if (-not $baseResolved.EndsWith([IO.Path]::DirectorySeparatorChar))
	{
		$baseResolved += [IO.Path]::DirectorySeparatorChar
	}

	$baseUri = [Uri]$baseResolved
	$targetUri = [Uri]$targetResolved
	$relativeUri = $baseUri.MakeRelativeUri($targetUri)

	[Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', [IO.Path]::DirectorySeparatorChar)
}

function Add-FileContent
{
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$StripTopParamBlock
    )

    Add-Content $OutputFile ""
    Add-Content $OutputFile "# ===================================================================="
    Add-Content $OutputFile "# Source: $(Get-RelativePathCompat -BasePath $ProjectRoot -TargetPath $Path)"
    Add-Content $OutputFile "# ===================================================================="
    Add-Content $OutputFile ""

    $content = Get-Content -LiteralPath $Path -Raw

    if ($StripTopParamBlock)
    {
		# Remove an optional leading attribute block (e.g. [CmdletBinding()]) plus script-level param().
		$content = $content -replace '(?s)\A(?=(?:.*\[CmdletBinding\(\)]|.*\bparam\s*\(.*?\))).*?\r?\n\s*\r?\n', ''

		# Remove standalone script entrypoint blocks when bundling into the unified script.
		$content = $content -replace '(?ms)^\s*if\s*\(\s*\$MyInvocation\.MyCommand\.Name\s*-eq\s*[^)]*\)\s*\{\s*.*?^\s*\}\s*[\r\n]*', ''
    }

    # Remove module-only export directives when flattening into a script
    $content = $content -replace '(?m)^\s*Export-ModuleMember\b.*(?:\r?\n)?', ''


    Add-Content -LiteralPath $OutputFile -Value $content
}

function Set-ScriptSignature
{
	param(
		[Parameter(Mandatory = $true)][string]$Path
	)

	$thumbprint = "123456789ABCDEF123456789ABCDEF123456789A" # Replace with your actual thumbprint
	if ($BuildType -eq "Release")
	{
		Write-Host "Searching for Code Signing certificate with thumbprint $thumbprint..."
		$cert = Get-ChildItem Cert:\CurrentUser\My\$thumbprint -CodeSigningCert
	}
	else
	{
		Write-Host "Creating self-signed Code Signing certificate..."
		$cert = New-SelfSignedCertificate `
			-Type CodeSigningCert `
			-Subject "CN=Resilio RslConnectToolkit" `
			-CertStoreLocation "Cert:\CurrentUser\My"
	}

	if ($cert)
	{
		if ($BuildType -eq "Release" -and $cert.Issuer -eq $cert.Subject)
		{
			throw "Self-signed certificate cannot be used for Release build."
		}

		Write-Host "Signing..."

		Set-AuthenticodeSignature `
			-FilePath $OutputFile `
			-Certificate $cert | Out-Null

		Write-Host ""
		Write-Host "Sign completed:" -ForegroundColor Green
		Write-Host "  $OutputFile" -ForegroundColor Green
	}
	else
	{
		Write-Host "No Code Signing certificate found. Skip signing." -ForegroundColor Yellow
	}

	Write-Host ""
}

@"
###############################################################################
# RslConnectToolkit, v1.0.0
# AUTO-GENERATED FILE
# DO NOT EDIT
###############################################################################

param(
	[Parameter(Position = 0)]
    [ValidateSet("Check","Setup")]
    [string]`$Action = "Check",
    # Check params
    [Parameter()]
	[string]`$Config = "Config",
    # Setup params
	[Parameter()]
	[string]`$NasuniShare = "",
	[Parameter()]
	[string]`$PrimaryAgent = ""
)

Set-StrictMode -Version Latest

`$ErrorActionPreference = "Stop"

"@ | Set-Content $OutputFile

Write-Host "Adding Modules from [$ProjectRoot\Modules]..."

Get-ChildItem "$ProjectRoot\Modules" -Filter *.psm1 -Recurse |
    Sort-Object FullName |
    ForEach-Object { 
		Write-Host "Adding module: $($_.FullName)"
		Add-FileContent -Path $_.FullName
	}

Write-Host "Adding Setup.ps1..."
Add-FileContent -Path "$ProjectRoot\Setup.ps1" -StripTopParamBlock

Write-Host "Adding Check.ps1..."
Add-FileContent -Path "$ProjectRoot\Check.ps1" -StripTopParamBlock

@"
###############################################################################
# Main script entry point

switch (`$Action)
{
	"Check"
	{
		Invoke-RslCheck -Config `$Config
	}
	"Setup" 
	{
		if ([string]::IsNullOrWhiteSpace(`$NasuniShare))
		{
			`$NasuniShare = Read-Host "Supply values for the parameter 'NasuniShare'"
		}

		Invoke-RslSetup -NasuniShare `$NasuniShare -PrimaryAgent `$PrimaryAgent
	}
}
"@ | Add-Content $OutputFile

Copy-Item -Path "$ProjectRoot\Config*.json" -Destination $ReleaseFolder -Force

Write-Host ""
Write-Host "Build completed:" -ForegroundColor Green
Write-Host "  $OutputFile" -ForegroundColor Green
Write-Host ""

if ($Signup)
{
	Set-ScriptSignature "$OutputFile"
}
