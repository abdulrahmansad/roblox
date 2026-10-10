$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

Assert-ProjectTool 'selene'
& selene src tests
if ($LASTEXITCODE -ne 0) { throw 'Selene reported lint issues.' }
