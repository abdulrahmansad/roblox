# Project status

Status: V1 implementation is in progress; **M7 — Persistence hardening** has passed portable acceptance and **M8 — Onboarding and mobile UI** is current. M1–M7 portable implementations and local verification are complete. Studio checks remain pending. The V1 design remains frozen.

## Current milestone: M8 — Onboarding and mobile UI

- M5 implements the shared 8-minute Raid phase cycle, server Raid IDs, replicated phase timing, a client countdown, and runtime 15-second grace for a player who joins during RAID. Its failed-session path also clears every replicated Raid attribute. `./scripts/verify.ps1` passes formatting, Selene (0 warnings/errors), 56 Lune tests, and the Rojo build.
- M6 implements server-measured theft channel/carry/bank, separate Tag validation/cooldown/immunity/stagger handling, recovery, per-Raid limits, Welcome participation/protection, and a write-ahead transfer journal. M7's changes are recorded in its completed milestone evidence.
- M7 adds revisioned profile backups, quarantine-before-restore, bounded store retries, strict journal validation/capacity, and interrupted-transfer recovery. The full portable pipeline passes formatting, lint (0 issues), 81 tests, and the Rojo build. Recovery rejects stale backups whose revision differs from the primary metadata. The locked schema has no previous persisted production version, so no fabricated migration was added; future schema upgrades must add a sequential migration and real fixture.
- M8 will build the locked first-session/mobile UI on top of the existing server actions and presentation hooks. Studio device simulation remains a separate pending check.

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
- **M4 — Mutations:** portable implementation and verification pass; Studio mutation-station checks remain pending. Commit `476f060937a3b39a4bc36f1ebb05c639a71f96da` is pushed to `origin/main`.
- **M5 — Raid state and arrival grace:** portable implementation and verification pass. Exact phase timing, Raid IDs, phase snapshots/events, countdown presentation, operational-readiness grace, and reset/rejoin behavior are covered; Studio phase presentation and multiplayer checks remain pending. Commit `f28a7165fcb9cc55291f5fb1dfc6118ca6752032` is pushed.
- **M6 — Theft, Tag, recovery, and Welcome protection:** portable implementation passed 70 tests with formatting, lint, and Rojo build green. Coverage includes server-side holds/range, locks and limits, Tag/drop/recovery, Welcome participation and protection, strict Raid-end banking, transient/ambiguous journal responses, and ActionService replay. Studio multiplayer remains pending; no live Roblox DataStore claim is made. Commit `20586f9dc2db59c367a3222e8892cc891a1a6d8c` is pushed.
- **M7 — Persistence hardening:** portable implementation passes 81 tests with formatting, lint, and Rojo build green. Coverage includes profile retries, revisioned backup/quarantine recovery, stale-backup rejection, future-version rejection, bounded transfer journal, PREPARED/COMMITTED replay, and shutdown during normal ownership, carry, and ambiguous bank commit. No earlier production schema exists under the locked version-1 data model, so no synthetic migration was created. Studio and live DataStore integration remain pending.

## Locked planning contracts

- V1 scope and balance are frozen in [GAME_DESIGN.md](GAME_DESIGN.md) and linked design documents.
- Architecture, profile schema, protocol, and state machines are in [ARCHITECTURE.md](ARCHITECTURE.md), [DATA_MODEL.md](DATA_MODEL.md), [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md), and [STATE_MACHINES.md](STATE_MACHINES.md).
- M0–M12 acceptance and commit boundaries are in [MILESTONES.md](MILESTONES.md).

## Toolchain and Studio status

Pinned tools: Rokit 1.2.0, Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, and Lune 0.10.5. The current full verification passes, including Rojo build. The Rojo serve workflow was previously verified at `localhost:34872` with HTTP 200.

Roblox Studio was not detected in the previously inspected PATH, LocalAppData/Program Files locations, Appx packages, or local plugin folder. Studio login and Rojo plugin status therefore cannot be checked. The human action is to install/sign in to Studio, install the Rojo 7 plugin, connect to `localhost:34872`, then run the M0–M7 Studio checks documented in [tests/multiplayer/README.md](../tests/multiplayer/README.md). This does not block the remaining portable milestones.

## Remaining work

M8–M12 remain: mobile onboarding/UI, V1 map/content/audio, hostile playtest and balance, the approved cosmetic pass after gameplay gates, and release readiness. M0–M7 engine-backed checks, 6–8-player validation, mobile/device testing, and account-side Game Pass setup remain unverified or pending. No full-game, multiplayer, mobile, security, or release-readiness claim is made.

## Git

The active branch is `main` and `origin` is `https://github.com/abdulrahmansad/roblox.git`. M6 commit `20586f9dc2db59c367a3222e8892cc891a1a6d8c` is pushed. Historical M3 backup copies remain in the local stashes.
