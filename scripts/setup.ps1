param(
    [switch]$NoTrustCheck
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

$rokitCommand = Get-Command rokit -ErrorAction SilentlyContinue
if (-not $rokitCommand) {
    $rokitExe = Join-Path $rokitBin 'rokit.exe'
    if (Test-Path $rokitExe) {
        $env:PATH = "$rokitBin;$env:PATH"
    } else {
        throw 'Rokit is required. Install it using https://github.com/rojo-rbx/rokit#installation, reopen PowerShell, and rerun setup.'
    }
}

$versionText = (& rokit --version)
if ($LASTEXITCODE -ne 0 -or $versionText -notmatch 'rokit\s+(\d+\.\d+\.\d+)') {
    throw "Could not determine Rokit version: $versionText"
}
$version = [version]$Matches[1]
if ($version -lt [version]'1.2.0') {
    throw "Rokit 1.2.0 or newer is required; found $versionText"
}

if ($NoTrustCheck) {
    & rokit install --no-trust-check
} else {
    & rokit install
}
if ($LASTEXITCODE -ne 0) { throw 'rokit install failed.' }

& wally install
if ($LASTEXITCODE -ne 0) { throw 'Wally dependency installation failed.' }

Write-Host 'Setup complete. Run ./scripts/verify.ps1 to validate the foundation.'
