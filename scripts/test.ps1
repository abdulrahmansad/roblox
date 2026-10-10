$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

Assert-ProjectTool 'lune'
& lune run tests/run.luau
if ($LASTEXITCODE -ne 0) { throw 'Lune tests failed.' }
