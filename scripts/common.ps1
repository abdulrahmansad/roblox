$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$rokitBin = Join-Path $env:USERPROFILE '.rokit\bin'
if (Test-Path $rokitBin) {
    $pathParts = $env:PATH -split ';'
    if ($rokitBin -notin $pathParts) {
        $env:PATH = "$rokitBin;$env:PATH"
    }
}

function Assert-ProjectTool([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is missing. Run ./scripts/setup.ps1."
    }
}
