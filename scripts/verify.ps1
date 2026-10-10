$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:RepoRoot

$steps = @(
    @{ Name = 'Formatting'; Script = 'format.ps1'; Arguments = @('-Check') },
    @{ Name = 'Lint'; Script = 'lint.ps1'; Arguments = @() },
    @{ Name = 'Tests'; Script = 'test.ps1'; Arguments = @() },
    @{ Name = 'Rojo build'; Script = 'build.ps1'; Arguments = @() }
)

foreach ($step in $steps) {
    Write-Host "== $($step.Name) =="
    & (Join-Path $PSScriptRoot $step.Script) @($step.Arguments)
    if ($LASTEXITCODE -ne 0) { throw "$($step.Name) failed." }
}

Write-Host 'All local verification steps passed.'
