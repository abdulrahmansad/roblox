$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

Assert-ProjectTool 'rojo'
& rojo serve default.project.json
if ($LASTEXITCODE -ne 0) { throw 'Rojo serve exited with an error.' }
