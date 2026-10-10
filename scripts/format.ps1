param([switch]$Check)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

Assert-ProjectTool 'stylua'
$styluaArgs = @()
if ($Check) { $styluaArgs += '--check' }
$styluaArgs += @('src', 'tests')
& stylua @styluaArgs
if ($LASTEXITCODE -ne 0) { throw 'StyLua reported formatting issues.' }
