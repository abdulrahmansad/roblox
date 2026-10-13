param(
    [Parameter()]
    [ValidateRange(1, 8)]
    [int]$ClientCount = 1
)

$ErrorActionPreference = 'Stop'

$minimumAvailableGiB = if ($ClientCount -eq 1) {
    1
} elseif ($ClientCount -lt 6) {
    2
} else {
    4
}

$operatingSystem = Get-CimInstance Win32_OperatingSystem
$availableGiB = [double]$operatingSystem.FreePhysicalMemory / 1MB
$totalGiB = [double]$operatingSystem.TotalVisibleMemorySize / 1MB

Write-Host ('Available physical memory: {0:N2} GiB of {1:N2} GiB.' -f $availableGiB, $totalGiB)
Write-Host ('Preflight for {0} client(s): requires at least {1} GiB available.' -f $ClientCount, $minimumAvailableGiB)

if ($availableGiB -lt $minimumAvailableGiB) {
    $message = 'NO-GO: defer Studio Play until at least {0} GiB is available.' -f $minimumAvailableGiB
    Write-Warning $message
    throw $message
}

Write-Host 'GO: the memory preflight passed. This does not replace Studio acceptance tests.' -ForegroundColor Green
