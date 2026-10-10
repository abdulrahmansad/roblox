# Testing strategy

## Local checks

`./scripts/verify.ps1` runs formatting validation, Selene, the Lune test suite, and a Rojo place build. `tests/run.luau` checks protocol and request validation, base/session lifecycle, profile defaults and validation, DataStore lease/save/retry behavior through a deterministic fake, rejoin restoration, capped Scrap, fractional online income, and no offline accrual.

TestEZ 0.4.1 is a Wally development dependency for tests that require Roblox engine behavior. `tests/testez.yml` identifies the discovery roots and `selene.toml` enables TestEZ globals. Studio/TestEZ execution is not available on machines without Roblox Studio.

## Studio integration and multiplayer

Use Studio Test mode for client/server smoke checks. Use **Server & Clients** for multiplayer. Studio supports up to eight simulated clients; the current foundation includes a documented manual workflow in `tests/multiplayer/README.md`. `StudioTestService` provides a future plugin-driven path for scripted sessions, mid-session joins, and disconnects. Never describe Lune as multiplayer simulation.

To run the current TestEZ specs in Studio's server command bar after syncing with Rojo:

```lua
local testEZ = require(game:GetService("ServerStorage").DevPackages.TestEZ)
testEZ.run(game:GetService("ServerStorage").FoundationTests, function(results)
	testEZ.Reporters.TextReporter.report(results)
end)
```

This engine-backed command was not run during bootstrap because Roblox Studio is not installed on the inspected machine.

## Required future coverage

- Unit: deterministic validators, config, domain calculations.
- Integration: server services with mocked persistence/network boundaries.
- Security: malformed payload, spoofed ownership, replay, duplicate requests, rate limits, phase and proximity rejection.
- Persistence: migrations, corrupt records, retry/exhaustion, session conflict, shutdown and recovery.
- Monetization: receipt idempotency, duplicate/retried receipts, entitlement checks, and failure handling.
- Studio multiplayer: two-player interaction and race tests, then 6–8 clients for join/leave and load behavior.

### Planned V1 design regression coverage

- Mutation odds: normal rolls use the documented table; Mythic remains exactly 0.1% on every normal roll, including a Rare-or-better pity roll. Across any 25 or more normal rolls without Mythic, no Mythic guarantee activates and no Mythic miss counter is stored. Verify the UI shows normal odds and exact conditional odds when Rare pity is active.
- Welcome protection: only the saved `welcomeCreatureId` is protected while `hasCompletedFirstRaid` is false. Any player already in the server at RAID start is marked as participating immediately, even if character/base initialization is still finishing. A RAID join is marked only if its original 15-second grace expires strictly before RAID-to-RESOLUTION. Verify the durable `{raidId, completesAtUnix}` marker survives disconnect/rejoin; after participation, protection expires at that Raid's RESOLUTION-to-COOLDOWN boundary even if the player is offline. A late join whose grace lasts through RAID end must not consume protection. PEACE and WARNING do not consume it.
- Raid arrival grace: a RAID join receives 15 seconds from operational readiness, blocks both targeting that player's base and their outgoing theft, and leaves the shared timer unchanged. PEACE/WARNING joins receive no special grace. Reset, respawn, and rejoin in the same server Raid reuse the original timestamp.
- Rewards: a successful Tag never grants a catalyst, including repeated or coordinated attempts. A successful theft deposit grants one chosen catalyst if the thief has not already earned one that Raid; duplicate/replayed requests do not grant another.

## Future implementation test matrix

These are required cases for the listed milestones; later gameplay coverage is not implemented yet. M1 has portable base/session/phase tests; M2 covers schema defaults, validation, lock/retry/save behavior through a fake DataStore, rejoin restoration, capped balances, and online-only income. Add assertions with the behavior they protect as each system is built. Use deterministic injected rolls and a controllable server clock, never statistical pass/fail thresholds for exact odds.

| Area | Cases and expected result | Test layer / milestone |
| --- | --- | --- |
| Capsules | Welcome purchase costs 120 Scrap, is available once, grants one server-selected Uncommon uniformly from the four; it does not touch pity. Standard capsule uses 70/25/5 tier odds and documented species selection. Three below-Uncommon outcomes guarantee at least Uncommon next; eight below-Rare guarantee Rare; Rare satisfies both; counters persist and reset correctly. Reject insufficient Scrap, full capacity, invalid phase, malformed IDs, and duplicate purchase without double charge/grant. | Unit + service integration; M3, M7 |
| Mutations | Normal roll costs 100 Scrap and one matching catalyst; tutorial is one free chosen-theme Common and excluded from pity. Inject deterministic rolls for every tier; Mythic is exactly 0.1% normally and remains 0.1% while Rare pity is active (99.9% Rare / 0.1% Mythic when guaranteed). After any number of Mythic misses there is no Mythic guarantee/counter. Duplicate start charges once; invalid phases, reserved creature, wrong theme, or insufficient balance reject. Keep-current, replace, and decline preserve the old form unless replace is chosen; no refund; only equipped forms enter Codex. | Unit + service integration; M4, M7 |
| Raid clock / joins | Verify exact phase order and 5:00/0:30/1:30/0:30/0:30 durations, including a transition at each boundary. Join in each phase inherits current phase. RAID join starts one 15-second grace at operational readiness; test before/at/after expiry, shared clock unchanged, both inbound and outbound theft blocked, and reset/respawn/rejoin never refreshes it. PEACE/WARNING do not grant grace or consume Welcome protection. | Unit + Studio integration; M1, M5 |
| First-Raid Welcome participation | Any player already in the server at RAID start becomes a participant immediately, including while character/base setup finishes. Join during RAID with grace expiry strictly before RAID-to-RESOLUTION becomes a participant at that exact expiry. Expiry equal to or after RAID-to-RESOLUTION does not qualify, even if it occurs during RESOLUTION; grace that lasts through RAID end leaves protection for a later Raid. Persist marker `{raidId, completesAtUnix}` immediately. Disconnect/rejoin before completion reuses it; disconnect after participation cannot save protection. At RESOLUTION-to-COOLDOWN, or on later profile load after that timestamp, set completion and expire only the Welcome creature's protection. Repeated loading/transition is idempotent. | Unit + persistence + Studio; M5–M7 |
| Theft | Race two thieves for one creature; race two creatures from one owner/base; enforce one owner loss, two attempted creatures, one bank per thief per Raid; full thief base rejects before attempt/reservation; full victim base does not block. Starter and protected Welcome instance reject. Check successful atomic transfer, failed save rollback/reconciliation, stale reservation recovery, same creature attempted once, and duplicate/replayed requests. Disconnect/reset either side, phase end during channel/carry, and bank timestamp before/equal/after boundary resolve once. Malformed payloads and client-supplied ownership/reward are rejected. | Unit + server integration + 2-client Studio; M6–M7 |
| Tag / recovery | Valid and invalid range, cooldown 6 seconds, Tagged thief immunity 5 seconds, channel cancel, carried drop, 1-second owner recovery within 5 seconds, and automatic return after 5 seconds. Test RAID boundary and player disconnect. Neither successful nor missed Tag grants a catalyst; only a successful deposit grants at most one chosen catalyst per thief per Raid. | Unit + server integration + 2-client Studio; M6 |
| Persistence | Round-trip all V1 fields; missing-field defaults; sequential migration; invalid version; out-of-range values; malformed references; corrupt payload quarantine/backup; transient save retry and exhausted failure; duplicate session lock; shutdown best-effort save; profile load after marker deadline finalizes protection; profile load before deadline reuses marker; duplicate transfer journal replay never duplicates ownership. | Unit + store integration; M2–M7 |
| Protocol/security | Exact allowlisted keys and bounded payload sizes; server derives Player identity, phase, price, rarity, costs, ownership, position, results, and entitlement; request IDs are idempotent; global/per-action rate limits run before expensive operations; rejection is safe and does not partially mutate state. | Unit + integration; M0, M3–M7, M11 |
| Studio UX / performance | M0 DevPing smoke, two-client server/client startup, interaction feedback, mobile touch targets and reduced effects; then 6–8 client join/leave and load scenarios; no duplicate assignments, transfers, stale ownership, or phase drift. | Studio manual/automated; M0, M1, M8–M10 |
| Monetization | Future pass entitlement refresh and receipt/purchase path are server-owned, idempotent, retry-safe, and cosmetic-only. This readiness phase creates no product IDs or remotes. | Service integration + Studio; M11 |

The complete milestone-to-test mapping is in [MILESTONES.md](MILESTONES.md). Studio-only coverage remains pending until Studio is installed and signed in.

Add tests alongside behavior; do not create always-pass placeholders.
