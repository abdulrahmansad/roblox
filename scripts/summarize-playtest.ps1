[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$prefix = '[OddlingsAnalytics] '
$knownEvents = @(
    'session_started', 'session_ended', 'capsule_purchased', 'first_capsule',
    'tutorial_mutation_completed', 'first_mutation', 'mutation_rolled',
    'scrap_earned', 'scrap_spent', 'slot_upgraded', 'slot3_purchased',
    'first_raid_participated', 'first_raid_completed', 'arrival_grace_started',
    'arrival_grace_expired', 'theft_protection_check', 'creature_lost',
    'theft_banked', 'tag_succeeded', 'creature_recovered', 'creature_auto_returned'
)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw 'The supplied playtest log file was not found.'
}

$events = [System.Collections.Generic.List[object]]::new()
$sessionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$malformedRecords = 0
$unknownEventRecords = 0
$ignoredLines = 0

foreach ($line in Get-Content -LiteralPath $Path) {
    if (-not $line.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        $ignoredLines++
        continue
    }

    try {
        $record = ConvertFrom-Json -InputObject $line.Substring($prefix.Length) -ErrorAction Stop
    }
    catch {
        $malformedRecords++
        continue
    }

    if (
        $null -eq $record -or
        $record -isnot [System.Management.Automation.PSCustomObject] -or
        $record.event -isnot [string] -or
        $record.sessionId -isnot [string] -or
        [string]::IsNullOrWhiteSpace($record.sessionId) -or
        $record.elapsedSeconds -is [bool] -or
        $record.properties -isnot [System.Management.Automation.PSCustomObject]
    ) {
        $malformedRecords++
        continue
    }

    $elapsedSeconds = 0.0
    try {
        $elapsedSeconds = [double]$record.elapsedSeconds
    }
    catch {
        $malformedRecords++
        continue
    }

    if ([double]::IsNaN($elapsedSeconds) -or [double]::IsInfinity($elapsedSeconds) -or $elapsedSeconds -lt 0) {
        $malformedRecords++
        continue
    }

    $null = $sessionIds.Add($record.sessionId)
    if ($record.event -notin $knownEvents) {
        $unknownEventRecords++
        continue
    }

    $events.Add([pscustomobject]@{
        Event = $record.event
        SessionId = $record.sessionId
        ElapsedSeconds = $elapsedSeconds
        Properties = $record.properties
    })
}

function Get-NumericStats([object[]]$Values) {
    $sorted = @($Values | ForEach-Object { [double]$_ } | Sort-Object)
    $count = $sorted.Count
    if ($count -eq 0) {
        return [pscustomobject][ordered]@{
            count = 0
            mean = $null
            median = $null
            p90 = $null
            min = $null
            max = $null
        }
    }

    $middle = [int][Math]::Floor($count / 2)
    if ($count % 2 -eq 0) {
        $median = ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }
    else {
        $median = $sorted[$middle]
    }

    $p90Index = [Math]::Max(0, ([int][Math]::Ceiling(0.9 * $count) - 1))
    $mean = ($sorted | Measure-Object -Average).Average
    return [pscustomobject][ordered]@{
        count = $count
        mean = [Math]::Round([double]$mean, 1)
        median = [Math]::Round([double]$median, 1)
        p90 = [Math]::Round([double]$sorted[$p90Index], 1)
        min = [Math]::Round([double]$sorted[0], 1)
        max = [Math]::Round([double]$sorted[$count - 1], 1)
    }
}

function Get-EventTimeStats([string]$EventName) {
    $values = @($events | Where-Object { $_.Event -eq $EventName } | ForEach-Object { $_.ElapsedSeconds })
    return Get-NumericStats -Values $values
}

function Get-PropertyStats([object[]]$Rows, [string]$PropertyName) {
    $values = @(
        $Rows |
            Where-Object { $null -ne $_.Properties.$PropertyName } |
            ForEach-Object { [double]$_.Properties.$PropertyName }
    )
    return Get-NumericStats -Values $values
}

function Get-ValueCounts([object[]]$Rows, [string]$PropertyName, [string[]]$AllowedValues) {
    $counts = [ordered]@{}
    foreach ($value in $AllowedValues) {
        $counts[$value] = 0
    }
    foreach ($row in $Rows) {
        $value = [string]$row.Properties.$PropertyName
        if ($counts.Contains($value)) {
            $counts[$value]++
        }
    }
    return [pscustomobject]$counts
}

function Get-EconomyTotals([string]$EventName, [string]$CategoryProperty, [string[]]$Categories) {
    $rows = @($events | Where-Object { $_.Event -eq $EventName })
    $totals = [ordered]@{}
    foreach ($category in $Categories) {
        $totals[$category] = 0.0
    }
    foreach ($row in $rows) {
        $category = [string]$row.Properties.$CategoryProperty
        if ($totals.Contains($category) -and $null -ne $row.Properties.amount) {
            $amount = 0.0
            if ([double]::TryParse([string]$row.Properties.amount, [ref]$amount) -and
                -not [double]::IsNaN($amount) -and -not [double]::IsInfinity($amount) -and $amount -ge 0) {
                $totals[$category] += $amount
            }
        }
    }
    $total = 0.0
    foreach ($amount in $totals.Values) {
        $total += $amount
    }
    foreach ($category in $Categories) {
        $totals[$category] = [Math]::Round([double]$totals[$category], 2)
    }
    return [pscustomobject][ordered]@{
        total = [Math]::Round($total, 2)
        byCategory = [pscustomobject]$totals
    }
}

$eventCounts = [ordered]@{}
foreach ($eventName in $knownEvents) {
    $eventCounts[$eventName] = @($events | Where-Object { $_.Event -eq $eventName }).Count
}

$starts = @($events | Where-Object { $_.Event -eq 'session_started' })
$losses = @($events | Where-Object { $_.Event -eq 'creature_lost' })
$endedAfterLoss = @(
    $events |
        Where-Object { $_.Event -eq 'session_ended' -and $null -ne $_.Properties.lossToExitSeconds }
)
$protectionChecks = @($events | Where-Object { $_.Event -eq 'theft_protection_check' })
$graceExpiry = @($events | Where-Object { $_.Event -eq 'arrival_grace_expired' })

$summary = [pscustomobject][ordered]@{
    summaryVersion = 1
    sessions = $sessionIds.Count
    eventCounts = [pscustomobject]$eventCounts
    dataQuality = [pscustomobject][ordered]@{
        malformedRecords = $malformedRecords
        unknownEventRecords = $unknownEventRecords
        ignoredNonAnalyticsLines = $ignoredLines
    }
    firstSession = [pscustomobject][ordered]@{
        newPlayerSessions = @($starts | Where-Object { $_.Properties.newPlayer -eq $true }).Count
        firstMutationSeconds = Get-EventTimeStats -EventName 'first_mutation'
        firstCapsuleSeconds = Get-EventTimeStats -EventName 'first_capsule'
        slot3PurchaseSeconds = Get-EventTimeStats -EventName 'slot3_purchased'
        firstRaidParticipationSeconds = Get-EventTimeStats -EventName 'first_raid_participated'
        firstRaidCompletionSeconds = Get-EventTimeStats -EventName 'first_raid_completed'
    }
    economy = [pscustomobject][ordered]@{
        scrapEarned = Get-EconomyTotals -EventName 'scrap_earned' -CategoryProperty 'source' -Categories @('income', 'sale')
        scrapSpent = Get-EconomyTotals -EventName 'scrap_spent' -CategoryProperty 'sink' -Categories @('capsule', 'catalyst', 'mutation', 'slot')
    }
    progression = [pscustomobject][ordered]@{
        mutationTiers = Get-ValueCounts -Rows @($events | Where-Object { $_.Event -eq 'mutation_rolled' }) -PropertyName 'tier' -AllowedValues @('Common', 'Uncommon', 'Rare', 'Mythic')
        rarePityActiveRolls = @($events | Where-Object { $_.Event -eq 'mutation_rolled' -and $_.Properties.rarePityActive -eq $true }).Count
        firstRaidParticipationReasons = Get-ValueCounts -Rows @($events | Where-Object { $_.Event -eq 'first_raid_participated' }) -PropertyName 'reason' -AllowedValues @('raid_start', 'arrival_grace_expired')
        eligibleArrivalGraceExpiries = @($graceExpiry | Where-Object { $_.Properties.eligible -eq $true }).Count
        ineligibleArrivalGraceExpiries = @($graceExpiry | Where-Object { $_.Properties.eligible -eq $false }).Count
    }
    theft = [pscustomobject][ordered]@{
        banks = @($events | Where-Object { $_.Event -eq 'theft_banked' }).Count
        losses = $losses.Count
        lossesByRarity = Get-ValueCounts -Rows $losses -PropertyName 'rarity' -AllowedValues @('Common', 'Uncommon', 'Rare')
        ownedSecondsObserved = Get-PropertyStats -Rows $losses -PropertyName 'ownedSeconds'
        tagOutcomes = Get-ValueCounts -Rows @($events | Where-Object { $_.Event -eq 'tag_succeeded' }) -PropertyName 'outcome' -AllowedValues @('Cancelled', 'Dropped')
        recoveries = @($events | Where-Object { $_.Event -eq 'creature_recovered' }).Count
        automaticReturns = @($events | Where-Object { $_.Event -eq 'creature_auto_returned' }).Count
        protectionChecks = [pscustomobject][ordered]@{
            total = $protectionChecks.Count
            actor = @($protectionChecks | Where-Object { $_.Properties.role -eq 'actor' }).Count
            target = @($protectionChecks | Where-Object { $_.Properties.role -eq 'target' }).Count
            starterProtected = @($protectionChecks | Where-Object { $_.Properties.starterProtected -eq $true }).Count
            welcomeProtected = @($protectionChecks | Where-Object { $_.Properties.welcomeProtected -eq $true }).Count
            ownerArrivalGrace = @($protectionChecks | Where-Object { $_.Properties.ownerArrivalGrace -eq $true }).Count
            thiefArrivalGrace = @($protectionChecks | Where-Object { $_.Properties.thiefArrivalGrace -eq $true }).Count
        }
        sessionExitsAfterLoss = [pscustomobject][ordered]@{
            count = $endedAfterLoss.Count
            timeToExitSeconds = Get-PropertyStats -Rows $endedAfterLoss -PropertyName 'lossToExitSeconds'
            byLossRarity = Get-ValueCounts -Rows $endedAfterLoss -PropertyName 'lossRarity' -AllowedValues @('Common', 'Uncommon', 'Rare')
        }
    }
    sourceRecords = [pscustomobject][ordered]@{
        parsedKnownEvents = $events.Count
    }
}

$summary | ConvertTo-Json -Depth 8
