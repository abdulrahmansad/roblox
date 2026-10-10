# Project status

Status: M1 session/base code is implemented and passes local verification. M0 Studio validation and M1 Studio join/leave validation remain human-blocked because Roblox Studio is not installed. Continue with M2 after this milestone is committed; do not claim M1's Studio integration as passed.

## Current milestone

**M1 — Session and base**

- Implemented: eight deterministic base slots, a temporary eight-pad greybox, join/leave session lifecycle, character spawn relocation, operational readiness, server phase snapshot inheritance, and cleanup on reset/leave.
- The M1 profile readiness hook is injectable and covered for failure; it currently defaults to success because M2/M7 persistence is not implemented yet.
- Portable verification: `./scripts/verify.ps1` passed formatting, Selene (0 errors/warnings), 11 Lune tests, and Rojo build.
- Studio two-client join/leave and visual spawn checks: pending.

## Completed planning contracts

- V1 scope and balance remain frozen in [GAME_DESIGN.md](GAME_DESIGN.md), [MVP.md](MVP.md), and the linked design documents.
- The implementation contracts remain in [ARCHITECTURE.md](ARCHITECTURE.md), [DATA_MODEL.md](DATA_MODEL.md), [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md), and [STATE_MACHINES.md](STATE_MACHINES.md).
- M0–M12 acceptance and commit boundaries remain in [MILESTONES.md](MILESTONES.md).

## Toolchain and Rojo

Pinned tools are installed at the committed versions: Rokit 1.2.0, Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, and Lune 0.10.5. TestEZ 0.4.1 is present in the ignored Wally package directory.

The latest `./scripts/verify.ps1` run passed. The `default.project.json` Rojo build succeeded. `./scripts/serve.ps1` listened on `localhost:34872` and returned HTTP 200; the serve process was stopped after the check.

## Studio blocker

Roblox Studio is not detected in PATH, the expected LocalAppData/Program Files installation folders, Appx packages, or the local plugin folder. Studio login and Rojo plugin sync cannot be checked. The exact human step is: install and sign in to Roblox Studio, install the Rojo 7 plugin, connect to `localhost:34872`, and complete the M0/M1 two-client smoke in [tests/multiplayer/README.md](../tests/multiplayer/README.md).

## Remaining implementation

M2–M12 are not started. The economy, creature catalog runtime, capsules, mutations, timed Raid cycle, theft/Tag, persistence, onboarding/UI, art/map/audio content, hostile playtest, cosmetic pass, and release gates remain. No Studio-based performance, mobile, security, or multiplayer claim is made.
