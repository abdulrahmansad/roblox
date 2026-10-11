# Implementation milestones M0–M12

These are the implementation contracts for the authorized V1 build. The design is frozen; follow [GAME_DESIGN.md](GAME_DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md), [DATA_MODEL.md](DATA_MODEL.md), [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md), and [STATE_MACHINES.md](STATE_MACHINES.md). Work in dependency order and do not skip ahead. Milestone numbers identify scope.

Each accepted milestone closes with one focused commit containing only its implementation, tests, and the docs listed below. Do not batch unrelated milestones. If acceptance fails, keep work in the same milestone and do not mark it complete.

## M0 — Studio/Rojo smoke

- **Goal / included:** Confirm Roblox Studio, Rojo sync, server/client startup, the existing harmless DevPing smoke, malformed request rejection, and a two-client workflow.
- **Non-goals:** All gameplay, new remotes, UI, profile data, or monetization.
- **Dependencies:** Current Rojo foundation and `default.project.json`.
- **Player-visible result:** No gameplay result; the foundation place opens and syncs cleanly in Studio.
- **Tests:** `scripts/verify.ps1`; Studio server/client smoke; invalid DevPing payload rejected; two clients can connect and see smoke output.
- **Acceptance:** Studio connects through the Rojo 7 plugin; place builds; server and two clients start; valid smoke succeeds and invalid input is safely rejected.
- **Docs:** `TOOLING.md`, `TESTING.md`, `tests/multiplayer/README.md`, `PROJECT_STATUS.md`.
- **Commit boundary:** One smoke/tooling fix commit after Studio evidence is recorded.

## M1 — Session and base

- **Goal / included:** Handle joins/leaves, session-ready ordering, assign/release one of eight plots, and expose operational character/base readiness.
- **Non-goals:** Creature income, capsules, mutation, timed raids, theft, cosmetics.
- **Dependencies:** M0; `SessionService`, `BaseService`, `PlayerDataService` composition.
- **Player-visible result:** Player enters one assigned base; leaving releases it for another player.
- **Tests:** Unit/service join/leave, duplicate assignment, all eight bases, character reset, failed profile load; Studio two-client join/leave (pending Studio installation).
- **Acceptance:** No duplicate plot; no ninth assignment; reset does not duplicate/release the base; failed load does not expose an unready profile; join/leave cleans up exactly once.
- **Current evidence:** Portable session/base/phase tests and Rojo build pass; Studio join/leave remains unverified while Studio is unavailable.
- **Docs:** `ARCHITECTURE.md`, `TESTING.md`, `PROJECT_STATUS.md` if workflow changes.
- **Commit boundary:** One session/base commit with its tests and no economy behavior.

## M2 — Starter and online income

- **Goal / included:** Create a `schemaVersion: 1` profile with the full DATA_MODEL.md field shape/defaults, persist the initial 50 Scrap, Mossling starter, and two slots; show income; credit online income every 10 seconds with fractional carry. Implement the baseline session lock/load/save path; M7 hardens migrations, corruption recovery, and transaction journals.
- **Non-goals:** Capsules, mutation, raids, offline income, second currency, sale, slot upgrades.
- **Dependencies:** M1; shared creature/economy definitions and `PlayerDataService`/`ProfileStore` baseline.
- **Player-visible result:** Mossling visibly earns 40 Scrap/min; after the free tutorial in M4 it earns 50.
- **Tests:** Default creation exactly once, online rate/fraction calculation, save/load baseline, no offline accrual, capped bounds and retry behavior.
- **Acceptance:** Server alone creates starter ID/profile; base rate is exact; no offline earnings; rejoin restores committed Scrap and starter without duplication.
- **Current evidence:** 24 portable Lune tests, strict profile validation, fake-DataStore lock/save/retry coverage, exact Mossling income, and Rojo build pass. Studio-backed DataStore API and live leaderboard checks remain pending because Studio is unavailable.
- **Docs:** `DATA_MODEL.md`, `ECONOMY.md`, `TESTING.md`, `PROJECT_STATUS.md`.
- **Commit boundary:** One profile-default/income commit; no unrelated persistence hardening.

## M3 — Capsules, sales, and capacity

- **Goal / included:** Welcome/standard capsules, all 12 species IDs, server-selected results, standard pity, duplicates, 60-Scrap sale, and permanent slot 3/4 purchases.
- **Non-goals:** Mutation, Robux products, player trade, offline income.
- **Dependencies:** M2; `CapsuleService`, `CreatureService`, `EconomyService`.
- **Player-visible result:** Player can claim one Welcome Uncommon, collect duplicates, sell non-starters, and reach four stands.
- **Tests:** Welcome one-time 120 Scrap / guaranteed Uncommon; standard 70/25/5 and deterministic pity floor cases; capacity/funds/phase; sale starter lock; slot costs/prerequisites; duplicate request and race tests.
- **Acceptance:** Server picks results; Welcome never changes pity and cannot be claimed twice; pity counters obey 3/8 floors; no purchase/sale exceeds capacity or bypasses cost; starter cannot be sold.
- **Current evidence:** Portable verification passes formatting, Selene with 0 warnings/errors, 37 Lune tests, and Rojo build. The tests cover 12 catalog entries, Welcome selection/one-time tracking, exact standard-odds boundaries and pity floors, insufficient Scrap/full capacity, unique IDs and duplicates, starter/Welcome protection flags, stand collection/capacity mapping, sale/slot rules, replay-body conflict, transport/action throttles, and response-send failure. Studio visual stand and in-world kiosk checks remain pending because Roblox Studio is unavailable.
- **Docs:** `ARCHITECTURE.md`, `CREATURES.md`, `ECONOMY.md`, `DATA_MODEL.md`, `NETWORK_PROTOCOL.md`, `SECURITY.md`, `TESTING.md`, `PROJECT_STATUS.md`.
- **Commit boundary:** One capsule/capacity commit with no mutation code.

## M4 — Mutations

- **Goal / included:** Three catalyst themes and their 60-Scrap kiosk purchase, 24 forms, one free tutorial Common, 100-Scrap normal roll, one Rare-or-better pity counter, result reveal and keep/replace/decline.
- **Non-goals:** Mythic pity, paid odds, multiple active forms, extra mutation systems.
- **Dependencies:** M2/M3; `MutationService`, shared form/odds definitions.
- **Player-visible result:** Player chooses a tutorial theme and can reveal and equip a mutation.
- **Tests:** Catalyst kiosk price/theme and transaction replay; mutation cost/catalyst; tutorial idempotency; each tier via deterministic RNG; 0.1% Mythic including pity-active odds; no Mythic counter; one pending transaction; form/Codex behavior; invalid phase/reserved creature; disconnect and phase-boundary choice.
- **Acceptance:** Server chooses outcomes; 8 below-Rare rolls guarantee Rare-or-better next, Mythic remains 0.1%; old form remains until Replace; KeepCurrent/Decline do not refund; only equipped form is discovered.
- **Current evidence:** `./scripts/verify.ps1` passes formatting, Selene with 0 warnings/errors, 48 Lune tests, and Rojo build. Deterministic coverage includes all 24 forms, every normal tier boundary, 8-miss pity and 999/1 odds, 0.1% Mythic under active pity and after 25 non-Mythic rolls, tutorial selection/idempotency, all three choices, duplicate results, equipped-form Codex validation, locks, station range, action replay, and phase/disconnect cleanup. Roblox Studio mutation-station presentation and in-world interaction checks remain pending because Studio is unavailable.
- **Docs:** `MUTATIONS.md`, `DATA_MODEL.md`, `NETWORK_PROTOCOL.md`, `STATE_MACHINES.md`, `TESTING.md`.
- **Commit boundary:** One mutation commit; no raid logic.

## M5 — Raid state and arrival grace

- **Goal / included:** Implement the shared 8-minute PEACE/WARNING/RAID/RESOLUTION/COOLDOWN cycle, phase presentation, server Raid IDs, and symmetric 15-second grace for a RAID join.
- **Non-goals:** Theft, Tag, weapons, private timers, phase manipulation.
- **Dependencies:** M1; `RaidService`, `BaseService`, shared raid config.
- **Player-visible result:** All players see the same phase/countdown; a mid-RAID arrival can get ready before attacking or being targeted.
- **Tests:** Exact durations and boundaries; join in every phase; readiness starts grace; one server-owned grace query is available to both eligibility checks; reset/rejoin in same Raid does not refresh; fake clock boundary tests. M6 integration proves incoming and outgoing theft are both blocked while grace is active.
- **Acceptance:** One clock per server; exact phase order; joins inherit current state; grace is 15 seconds from operational readiness and never extends or pauses Raid. M6 consumes the shared server query for both theft directions.
- **Current evidence:** Portable acceptance passes: exact phase durations/boundaries, drift-free catch-up, one Heartbeat binding, Raid IDs, phase snapshots/change signal, joins in every phase, operational-readiness grace, strict expiry, late join, reset/rejoin behavior, invalid phase-action rejection, and cleanup after failed session initialization. The M5 verification run passed formatting, Selene (0 errors/warnings), 56 Lune tests, and Rojo build. Studio phase presentation and multiplayer join/reset checks remain pending; M6 adds the tested Welcome participation transitions.
- **Docs:** `RAIDS.md`, `STATE_MACHINES.md`, `NETWORK_PROTOCOL.md`, `TESTING.md`, `PLAYER_FLOW.md`.
- **Commit boundary:** One Raid clock/grace commit without theft or Tag.

## M6 — Theft, Tag, recovery, Welcome protection

- **Goal / included:** Target/base locks, 2.5-second channel, carried/drop/return/bank, two attempts/one bank per thief, one loss per owner, Tag, 5-second recovery, and exact first-Raid Welcome marker transitions.
- **Non-goals:** Weapons, extra defenses, multi-item carry, currency theft, trading.
- **Dependencies:** M3, M5, and PlayerDataService's durable marker fields from the V1 schema. M7 hardens recovery and migrations after these state writes exist.
- **Player-visible result:** A player can make one risky creature run, defend with Tag, and recover a dropped creature.
- **Tests:** Full theft and Tag matrix in `TESTING.md`, including races, locks, ownership, disconnections, phase end, timestamp tie, persistence fail/recovery, immediate participation at Raid start, grace-expiry participation, disconnect after participation, late grace through Raid end, post-completion Welcome claim, and offline completion finalization.
- **Acceptance:** Server-only ownership; strict bank-before-end; attempts/limits exact; starter and active Welcome target protected; `firstRaidParticipation` is persisted idempotently at qualification and never replaced; reconnect cannot refresh grace or entitlement; at completion timestamp Welcome protection expires even while offline, and a later Welcome claim stays unprotected; no Tag catalyst.
- **Docs:** `RAIDS.md`, `SECURITY.md`, `DATA_MODEL.md`, `STATE_MACHINES.md`, `NETWORK_PROTOCOL.md`, `ANALYTICS.md`, `TESTING.md`.
- **Commit boundary:** One theft/Tag commit with transfer journal integration and required race tests.
- **Current evidence:** Portable suite passes 70 tests; canonical verification passes formatting, Selene (0 errors/warnings), Lune, and Rojo build. Tests cover theft locks/limits, 2.5-second channel, carry speed/jump/tool restrictions, journaled bank, exact Raid-end boundary, Tag cooldown/immunity/stagger, drop/recovery/auto-return, disconnections/resets, first-Raid participation and Welcome expiration, malformed/replayed requests, plus transient and ambiguous journal responses. Two-client/Studio behavior and live DataStore semantics remain pending; M7 continues crash/restart and storage hardening.

## M7 — Persistence hardening

- **Goal / included:** Complete V1 profile durability for every schema field; version checks, session locks, validation, backup/quarantine, bounded retries, shutdown behavior, and transfer-recovery journal guarantees. Add sequential migration functions only when a real earlier schema exists to migrate.
- **Non-goals:** Offline income, cross-server trade, Mythic pity, unapproved profile fields.
- **Dependencies:** M2–M6 domain mutations; `PlayerDataService` and `ProfileStore`.
- **Player-visible result:** Progress, pity, Codex, tutorial, and first-Raid protection survive leaving/rejoining without duplicate creatures or rewards.
- **Tests:** Full round-trip/default/missing-field/version/corruption/lock/retry/shutdown suite; restart and duplicate-journal recovery for capsule, sale, mutation, and theft transactions.
- **Acceptance:** The saved record matches DATA_MODEL.md exactly; no unknown-version overwrite; corrupt data is quarantined/recovered rather than reset; session conflicts block a second writer; interrupted transfers resolve to one owner; offline income remains zero.
- **Docs:** `DATA_MODEL.md`, `SECURITY.md`, `ARCHITECTURE.md`, `TESTING.md`, `PROJECT_STATUS.md`.
- **Commit boundary:** One persistence hardening commit; do not include unrelated UX/content.
- **Current evidence:** Canonical verification passes formatting, Selene (0 errors/warnings), 81 Lune tests, and Rojo build. Portable coverage includes exact profile round-trip, session takeover/rejection, exhausted save retry, valid/invalid/missing and stale-revision backup, quarantine-before-restore, future-version fail-closed, strict bounded journal retry/schema/capacity, PREPARED rollback, COMMITTED replay, and shutdown with normal ownership, carried state, and an ambiguous bank. No earlier persisted schema exists in the locked data model, so no fabricated migration was added; a legacy schema fixture is required when a future schema bump introduces a real migration. Live DataStore and Studio checks remain pending.

## M8 — Onboarding and mobile UI

- **Goal / included:** 20-second guided tutorial, goal card, touch prompts, readable rarity, caption/visual alerts, reduced effects, and error/success feedback.
- **Non-goals:** Inventory grid, extra panels, new systems, mandatory tutorial wait.
- **Dependencies:** M2–M6 server flows and M0 Studio path.
- **Player-visible result:** A first-time phone player can choose the free mutation, reach Welcome Capsule, and understand the next goal.
- **Tests:** Touch target size >=52 px, keyboard/touch parity, accessibility labels, skip/leave/resume, server response states, Studio phone emulation and two-client presentation.
- **Acceptance:** Tutorial mutation is one-time and immediate; all core actions have clear touch controls; UI reflects server state; audio cues have visual alternatives.
- **Docs:** `PLAYER_FLOW.md`, `GAME_DESIGN.md`, `TESTING.md`, `PROJECT_STATUS.md`.
- **Commit boundary:** One onboarding/UI commit, no new economy or raid rules.
- **Current evidence:** Portable verification passes formatting, Selene (0 issues), 84 Lune tests, and Rojo build. The client now has the locked first-session theme choice and goal flow, skippable guidance that preserves the free mutation, compact economy HUD, affordable commerce/mutation controls, rarity/odds/error presentation, contextual touch/keyboard actions, radial hold progress, and a local recovery marker. Snapshot Welcome availability is server-derived; dropped positions are sent only to the owner and thief. The HUD model, skipped-guide goal, Welcome snapshot field, event privacy, and completed theft-hold cancellation boundary have portable regression coverage. Roblox Studio phone emulation, real touch input, two-client presentation, and device accessibility remain pending and are not claimed as passed. M9 adds the locked audio cues; captions already provide visual alternatives.

## M9 — MVP content and audio

- **Goal / included:** Complete 12 readable species, 24 reusable form recipes across four rigs, three functional zones on one map, 36-entry Codex presentation, and specified cue set.
- **Non-goals:** New worlds, 288 bespoke models, full soundtrack, new forms/species.
- **Dependencies:** M2–M8; shared catalogs and locked visual recipes.
- **Player-visible result:** Complete collection and mutation presentation in the single compact world.
- **Tests:** Catalog has 12/24/36 entries; every species/form is identifiable; no hitbox/movement change; mobile readability, asset load and audio visual alternatives.
- **Acceptance:** No missing IDs or display recipes; map routes and three zones meet the approved footprint; mutation effects preserve readability and performance budget.
- **Docs:** `CREATURES.md`, `MUTATIONS.md`, `GAME_DESIGN.md`, `TESTING.md`.
- **Commit boundary:** One content/art integration commit after all catalogs validate.
- **Current evidence:** Portable verification passes formatting, Selene (0 warnings/errors), 86 Lune tests, and the Rojo build. Coverage verifies 12 species / 4 rigs, 24 mutation recipes, all 36 Codex entries, map footprint/base-ring geometry, online-income notification safety, participant-only recovery reasons, and a global Mythic notice only after a successful equipped Replace. The local blockout now has Commons/Chase Loop/Base Ring labels, route segments, stand-based local creature models, an on-demand Codex, and presentation cues with reduced-effects controls. Studio is installed and connected through Rojo; model/material inspection, sound asset load, mobile readability, instance/performance review, and multiplayer presentation remain pending after local test clients crashed with graphics driver error `0x887a0020` before joining.

## M10 — Balance and abuse playtest

- **Goal / included:** Measure onboarding timing, capsule/mutation economy, mobile chase/Tag, theft frustration, exploits, and 6–8-player behavior with telemetry and moderated sessions.
- **Non-goals:** Feature expansion, paid power, release to public, balance changes without evidence.
- **Dependencies:** M0–M9 complete; test place and telemetry boundary operational.
- **Player-visible result:** A stable private test build and evidence-backed adjustments within approved V1 scope.
- **Tests:** Full automated suite, server security/race tests, phone/tablet checks, 2-client and 6–8-client Studio sessions, first-session and loss/recovery analytics review.
- **Acceptance:** No duplication, stale ownership, phase race, or profile loss; first capsule/raid timing and loss-driven exits are measured; defined playtest gates in MVP.md are met or a documented design change is approved.
- **Current evidence:** The server-only telemetry boundary now writes allowlisted, session-correlated diagnostic events for first-session actions, Scrap flows, mutation tier/pity, first-Raid participation and completion, arrival-grace eligibility, server-derived theft protection status, committed theft/loss, Tag/recovery, and session exits. It omits account and creature identifiers and has no external provider. The offline `scripts/summarize-playtest.ps1` groups captured private-session logs into progression, economy, Raid/grace, theft, and loss-exit summaries without exposing session tokens or deciding subjective acceptance gates; its fixture checks run in canonical verification. The portable pipeline passes formatting, Selene (0 issues), 88 Lune tests, summary fixture checks, and the Rojo build. Static review found no reproducible authority or transfer defect and no balance change was justified. The world is bounded to 8 player bases and at most 32 local creature displays; server lifecycle and interaction loops are bounded by player/attempt state, and no per-frame creature rebuild loop was found. The unpublished local place first failed during DataStore bootstrap; the guarded volatile Studio store now reaches `[Foundation] Server initialized`. Two local test clients then crashed with graphics driver error `0x887a0020` before joining, so no client ping or multiplayer interaction was verified. Both were test instances of the same Rojo-built place; no new experience was created or published. Studio phone/tablet checks, 2- and 6–8-client sessions, live persistence integration, measured performance, and observed progression/loss-exit gates remain pending; M10 is not accepted.
- **Docs:** `MVP.md`, `ANALYTICS.md`, `TESTING.md`, `PROJECT_STATUS.md`, and affected design pages only when a decision is approved.
- **Commit boundary:** Separate bug-fix/balance commits by evidence-backed issue; no broad feature commit.

## M11 — Cosmetic monetization

- **Goal / included:** After gameplay gates pass, add the single 99 Robux Curator's Palette Game Pass with three alternate palettes and pedestal trim.
- **Non-goals:** Developer Products, paid power/luck/speed/recovery, randomized paid rewards, shop expansion.
- **Dependencies:** M10 accepted; creator account/product setup; server entitlement contract.
- **Player-visible result:** Buyer gets permanent cosmetics with no gameplay advantage; non-buyers retain the full V1 loop.
- **Tests:** Server ownership refresh success/failure, repeated checks, purchase completion, no client grant, no stat/capacity/visibility/raid impact.
- **Acceptance:** Product ID exists only in server config after Creator Hub setup; cosmetic grant is idempotent; service failure never fabricates entitlement; approved price/product matches MONETIZATION.md.
- **Docs:** `MONETIZATION.md`, `NETWORK_PROTOCOL.md`, `SECURITY.md`, `TESTING.md`.
- **Commit boundary:** One cosmetic pass commit after account/product review; no extra products.

## M12 — Release readiness

- **Goal / included:** Final mobile/device matrix, persistence recovery, moderation/privacy, performance, accessibility, launch operations, rollback, and support ownership review.
- **Non-goals:** Unreviewed features or public launch before creator/account gates pass.
- **Dependencies:** M7–M11 accepted; current Creator Hub/product and platform requirements checked.
- **Player-visible result:** A release candidate whose approved V1 loop is tested and supportable.
- **Tests:** Full regression on target devices, load/performance, exploit review, persistence restore, moderation/privacy review, and launch/rollback rehearsal.
- **Acceptance:** No open release-blocking defect; checklist is signed off with evidence; rollback and support owner are known; Creator Rewards terms/eligibility are verified at that time and never assumed as revenue.
- **Docs:** `BUILD_START_CHECKLIST.md` evolves into release checklist; `TOOLING.md`, `TESTING.md`, `MONETIZATION.md`, `PROJECT_STATUS.md`.
- **Commit boundary:** One release-readiness commit for checklists and evidence; publishing the experience is a separate explicitly authorized action.
- **Current evidence:** The release checklist now includes incident intake, triage, source/place rollback steps, data-integrity cautions, and current Roblox Version History/safety references. It is preparation only: no rollback was rehearsed, no support owner was named, and M7–M11/live Studio and Creator Hub gates remain incomplete.
