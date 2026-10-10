# Project status

Status: V1 implementation is in progress at **M4 — Mutations**. M1–M3 are committed and pushed. M3's portable implementation and full local verification pass are complete; Studio checks remain pending. The V1 design remains frozen.

## Current milestone: M4

- M4 implementation is beginning from the approved mutation catalog, odds, tutorial, and choice contracts in [MUTATIONS.md](MUTATIONS.md), [DATA_MODEL.md](DATA_MODEL.md), [STATE_MACHINES.md](STATE_MACHINES.md), and [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md). No M4 runtime implementation has been committed yet.
- M3 remains portable-verified as summarized below; engine-backed Studio checks remain pending.

## M3 — Capsules, sales, and capacity

- Implemented server-selected Welcome and Standard Capsules, all 12 species definitions, persistent standard-capsule pity, stable creature IDs, duplicate species, one-time Welcome tracking, starter/Welcome theft-protection checks, fixed 60-Scrap sales, Slot 3/4 purchases, and four blockout stand/display slots per base.
- Added the centralized M3 `ActionRequest`, `ActionResult`, and `DomainEvent` remotes for `PurchaseCapsule`, `SellCreature`, `PurchaseSlot`, and `GetSnapshot`. Requests validate exact payload shapes, session identity, server-observed operational state/proximity, transport/action throttles, and replay bodies.
- Player profiles project their current creature IDs, species, mutation IDs, and capacity to server-owned base stands after session load and each M3 collection/capacity mutation. Capsule, sale, and slot balance changes refresh the online leaderboard immediately.
- `./scripts/verify.ps1` passes formatting, Selene (0 warnings/errors), 37 Lune tests, and the Rojo build. Tests cover the M3 odds boundaries, pity floors, capacity/funds rejection, duplicate species/unique IDs, starter and Welcome protection, stand mapping, commerce, action replay/rate limits, and response delivery after disconnect.
- Studio rendering, kiosk proximity, and two-client stand replication checks remain pending because Roblox Studio is not installed. Portable tests do not claim engine or multiplayer validation.

## Completed milestones

- **M1 — Session and base:** eight deterministic base slots, temporary greybox, join/leave lifecycle, character spawn relocation, phase snapshot inheritance, operational readiness, and cleanup. Portable checks pass; Studio checks are pending.
- **M2 — Starter and online income:** validated profile defaults and persistence adapter, session lock/save/retry coverage, stable starter, exact 40 Scrap/min income, online-only 10-second payouts with fractional carry, and leaderboard values. Portable checks pass; live DataStore and Studio checks are pending.
- **M3 — Capsules, sales, and capacity:** portable implementation and verification pass as described above; Studio check pending. Commit `10a4f4846c79d89fbe13424abcaffb93f7f0e273` is pushed to `origin/main`.

## Locked planning contracts

- V1 scope and balance are frozen in [GAME_DESIGN.md](GAME_DESIGN.md) and linked design documents.
- Architecture, profile schema, protocol, and state machines are in [ARCHITECTURE.md](ARCHITECTURE.md), [DATA_MODEL.md](DATA_MODEL.md), [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md), and [STATE_MACHINES.md](STATE_MACHINES.md).
- M0–M12 acceptance and commit boundaries are in [MILESTONES.md](MILESTONES.md).

## Toolchain and Studio status

Pinned tools: Rokit 1.2.0, Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, and Lune 0.10.5. The current full verification passes, including Rojo build. The Rojo serve workflow was previously verified at `localhost:34872` with HTTP 200.

Roblox Studio is not detected in the inspected PATH, LocalAppData/Program Files locations, Appx packages, or local plugin folder. Studio login and Rojo plugin status therefore cannot be checked. The human action is to install/sign in to Studio, install the Rojo 7 plugin, connect to `localhost:34872`, then run the M0 two-client smoke and M1/M2/M3 Studio checks documented in [tests/multiplayer/README.md](../tests/multiplayer/README.md). This does not block the remaining portable milestones.

## Remaining work

M4–M12 remain: mutations, timed Raid state, theft/Tag/recovery, persistence hardening and transfer journals, mobile onboarding/UI, V1 map/content/audio, hostile playtest and balance, the approved cosmetic pass after gameplay gates, and release readiness. M0/M1/M2/M3 engine-backed checks, 6–8-player validation, mobile/device testing, and account-side Game Pass setup remain unverified or pending. No full-game, multiplayer, mobile, security, or release-readiness claim is made.

## Git

The active branch is `main` and `origin` is `https://github.com/abdulrahmansad/roblox.git`. Local `HEAD` and `origin/main` match at `10a4f4846c79d89fbe13424abcaffb93f7f0e273`, the M3 milestone commit. Historical M3 backup copies remain in the local stashes.
