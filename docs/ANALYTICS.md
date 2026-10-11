# Analytics foundation

## Status and data handling

M10 adds a server-only playtest telemetry boundary in `src/server/analytics/Telemetry.luau`. It writes bounded JSON event lines to the server output with the `[OddlingsAnalytics]` prefix. There is no external analytics provider, DataStore, or client-submitted analytics path. The local output is a developer diagnostic for controlled private sessions; it is not durable or aggregated across servers.

Events use the existing server-generated session token and elapsed time. The serialized records omit account IDs, player names, creature IDs, precise positions, arbitrary payloads, and mutation transaction IDs. The token is temporary and supports correlation only within one session. The service uses UserIds only as an in-memory key to route server events to the correct active session.

`ownedSeconds` on a loss event measures how long the server observed that creature in the current session. For creatures already owned when the profile loaded, this is a lower bound; the locked profile schema does not store acquisition timestamps. A playtest should use known acquisition times when evaluating total time invested.

## Current event contract

All event names and properties are allowlisted in `Telemetry.luau`; invalid fields are rejected. Events currently include:

- `session_started` and `session_ended`, with first-session eligibility, session duration, and time between the most recent committed loss and exit when applicable.
- `capsule_purchased` and `first_capsule`, with capsule kind and server-selected rarity.
- `tutorial_mutation_completed`, `first_mutation`, and `mutation_rolled`, including the server-selected tier and whether Rare-or-better pity was active.
- `slot_upgraded` and `slot3_purchased`.
- `scrap_earned` and `scrap_spent`, with source/sink category and server-calculated amount.
- `first_raid_participated` and `first_raid_completed`, including the server-determined participation reason.
- `arrival_grace_started` and `arrival_grace_expired`, with whether the strict Raid-end eligibility boundary was met.
- `theft_protection_check`, `creature_lost`, `theft_banked`, `tag_succeeded`, `creature_recovered`, and `creature_auto_returned`, with only low-cardinality protection/rarity/outcome fields. Protection checks record whether the starter, Welcome creature, or either player's arrival grace applied, split between actor and target sessions.

First-session timing is measured from the server-observed join callback, including profile-load time. First-capsule timing is emitted for a profile that still has only its starter and no Welcome creature; first-mutation and first-Raid events are limited by their server-owned progression state. A successful bank is recorded after journal commit and ownership application. Tag events are recorded only after a successful server-validated Tag.

## Playtest use

Use the server output for controlled, private sessions. Aggregate first-capsule and first-Raid elapsed times, mutation tiers/pity state, Scrap sources and sinks, loss rarity and observed ownership duration, Tag/recovery outcomes, and exits after a loss. Do not treat portable tests or these logs as a substitute for Studio playtests. A provider integration and retention policy require separate review before production collection.

Candidate future events include cohort return sessions and purchase funnel/completion. These are not currently emitted. Any provider or additional fields must preserve server authority, minimize personal data, and avoid raw client payloads.
