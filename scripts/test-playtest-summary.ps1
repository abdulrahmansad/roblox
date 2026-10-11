$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$fixturePath = Join-Path $script:RepoRoot 'tests/fixtures/playtest-analytics.txt'
$summaryScript = Join-Path $PSScriptRoot 'summarize-playtest.ps1'
$summaryJson = (& $summaryScript -Path $fixturePath | Out-String)
$summary = $summaryJson | ConvertFrom-Json -ErrorAction Stop

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) {
        throw "$Name expected '$Expected', got '$Actual'."
    }
}

Assert-Equal $summary.summaryVersion 1 'Summary version'
Assert-Equal $summary.sessions 3 'Distinct session count'
Assert-Equal $summary.sourceRecords.parsedKnownEvents 21 'Recognized event count'
Assert-Equal $summary.dataQuality.malformedRecords 2 'Malformed event count'
Assert-Equal $summary.dataQuality.unknownEventRecords 1 'Unknown event count'
Assert-Equal $summary.dataQuality.ignoredNonAnalyticsLines 1 'Ignored output line count'
Assert-Equal $summary.firstSession.newPlayerSessions 2 'New player session count'
Assert-Equal $summary.firstSession.firstCapsuleSeconds.count 2 'First capsule sample count'
Assert-Equal $summary.firstSession.firstCapsuleSeconds.median 105 'First capsule median seconds'
Assert-Equal $summary.firstSession.firstCapsuleSeconds.p90 120 'First capsule p90 seconds'
Assert-Equal $summary.firstSession.firstRaidParticipationSeconds.p90 300 'First Raid p90 seconds'
Assert-Equal $summary.economy.scrapEarned.total 100 'Scrap earned total'
Assert-Equal $summary.economy.scrapSpent.byCategory.catalyst 60 'Catalyst spend total'
Assert-Equal $summary.progression.mutationTiers.Rare 1 'Rare mutation count'
Assert-Equal $summary.progression.rarePityActiveRolls 1 'Rare pity roll count'
Assert-Equal $summary.progression.ineligibleArrivalGraceExpiries 1 'Ineligible grace expiry count'
Assert-Equal $summary.theft.lossesByRarity.Rare 1 'Rare loss count'
Assert-Equal $summary.theft.ownedSecondsObserved.median 600 'Observed ownership median'
Assert-Equal $summary.theft.tagOutcomes.Dropped 1 'Dropped Tag count'
Assert-Equal $summary.theft.protectionChecks.welcomeProtected 1 'Welcome protection check count'
Assert-Equal $summary.theft.sessionExitsAfterLoss.timeToExitSeconds.median 90 'Loss-to-exit median seconds'

if ($summaryJson.Contains('fixture-session-')) {
    throw 'Summary output must not expose session identifiers.'
}

Write-Host 'Playtest summary fixture passed.'
