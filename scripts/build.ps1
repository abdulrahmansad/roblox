$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

Assert-ProjectTool 'rojo'
$buildDir = Join-Path $script:RepoRoot 'build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
& rojo build default.project.json --output (Join-Path $buildDir 'foundation.rbxlx')
if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
