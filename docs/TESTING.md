# Testing strategy

## Local checks

`./scripts/verify.ps1` runs formatting validation, Selene, the Lune test suite, and a Rojo place build. `tests/run.luau` contains real checks against the shared protocol and server request service, including malformed client-style input.

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
- Welcome protection: only the saved `welcomeCreatureId` is protected, and only while `hasCompletedFirstRaid` is false. Verify the state survives disconnect/rejoin, remains active if the player is disconnected at the first Raid completion boundary, and ends at the RESOLUTION-to-COOLDOWN boundary for a connected participant.
- Raid arrival grace: a RAID join receives 15 seconds from operational readiness, blocks both targeting that player's base and their outgoing theft, and leaves the shared timer unchanged. PEACE/WARNING joins receive no special grace. Reset, respawn, and rejoin in the same server Raid reuse the original timestamp.
- Rewards: a successful Tag never grants a catalyst, including repeated or coordinated attempts. A successful theft deposit grants one chosen catalyst if the thief has not already earned one that Raid; duplicate/replayed requests do not grant another.

These are future behavior tests for gameplay implementation; this design-only correction does not add runtime code or tests.

Add tests alongside behavior; do not create always-pass placeholders.
