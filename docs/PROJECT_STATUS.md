# Project status

Status: M2 starter/profile/online-income code is implemented and passes local verification. M0 Studio validation, M1 Studio join/leave validation, and M2 live DataStore/leaderboard validation remain pending because Roblox Studio is not installed. Continue with M3 after the M2 commit is pushed; no Studio integration is claimed.

## Current milestone

**M2 — Starter and online income**

- Implemented: full version-1 profile defaults and strict validation; atomic DataStore session lease in key metadata; bounded retries; autosave, leave save, and shutdown save; stable starter ID; exact 40 Scrap/min Mossling rate; 10-second online payouts with runtime fractional carry; replicated leaderboard balance/rate.
- Profile loading completes before a player receives a base. Lock conflicts, unknown schemas, invalid profiles, and exhausted DataStore retries reject the player without replacing saved data.
- Portable verification: `./scripts/verify.ps1` passed formatting, Selene (0 errors/warnings), 24 Lune tests, and Rojo build.
- Studio two-client session smoke and live DataStore/API-services/leaderboard behavior: pending.

## Completed milestones

- **M1 — Session and base:** eight deterministic base slots, temporary eight-pad greybox, join/leave lifecycle, character spawn relocation, readiness, phase snapshot inheritance, and cleanup on reset/leave. Portable tests pass; Studio checks are pending.
- **M2 — Starter and online income:** portable schema, persistence adapter, lock/save/retry fake-store coverage, rejoin restoration, cap checks, and fractional online income pass. Studio checks are pending.

## Completed planning contracts

- V1 scope and balance remain frozen in [GAME_DESIGN.md](GAME_DESIGN.md), [MVP.md](MVP.md), and the linked design documents.
- The implementation contracts remain in [ARCHITECTURE.md](ARCHITECTURE.md), [DATA_MODEL.md](DATA_MODEL.md), [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md), and [STATE_MACHINES.md](STATE_MACHINES.md).
- M0–M12 acceptance and commit boundaries remain in [MILESTONES.md](MILESTONES.md).

## Toolchain and Rojo

Pinned tools are installed at the committed versions: Rokit 1.2.0, Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, and Lune 0.10.5. TestEZ 0.4.1 is present in the ignored Wally package directory.

The latest `./scripts/verify.ps1` run passed. The `default.project.json` Rojo build succeeded. `./scripts/serve.ps1` listened on `localhost:34872` and returned HTTP 200; the serve process was stopped after the check.

## Studio blocker

Roblox Studio is not detected in PATH, the expected LocalAppData/Program Files installation folders, Appx packages, or the local plugin folder. Studio login and Rojo plugin sync cannot be checked. The exact human step is: install and sign in to Roblox Studio, install the Rojo 7 plugin, connect to `localhost:34872`, and complete the M0/M1 two-client smoke plus M2 live DataStore/leaderboard check in [tests/multiplayer/README.md](../tests/multiplayer/README.md).

## Remaining implementation

M3–M12 are not started. Remaining work includes capsules, mutations, timed Raid cycle, theft/Tag, analytics integration, onboarding/UI, art/map/audio content, hostile playtest, cosmetic pass, and release gates. M7 still needs migration, backup/quarantine recovery, and transaction journals. No Studio-based performance, mobile, security, or multiplayer claim is made.
