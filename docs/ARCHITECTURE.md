# Architecture

V1 uses one server-authoritative service layer, a small shared definitions/protocol layer, and client controllers for input and display. This is the locked implementation plan for the authorized V1 build.

## Source of truth and runtime mapping

The filesystem is authoritative. Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to `ServerScriptService.Server`, and `src/client` to `StarterPlayer.StarterPlayerScripts.Client`. Wally-generated development packages are mapped under `ServerStorage.DevPackages`, and the TestEZ spec tree is mapped to `ServerStorage.FoundationTests`; generated package sources and place builds are ignored by Git. `default.project.json` is the single project map.

## Boundaries

- `shared`: protocol types, constants, deterministic utilities, and non-secret configuration. Treat replicated code and data as public.
- `server`: service orchestration, validation, ownership, persistence, economy, rewards, purchase fulfillment, and all authoritative decisions.
- `client`: input, presentation, effects, and requests. A client response or local state never proves ownership or entitlement.
- `tests`: portable Lune tests plus Roblox-native TestEZ and Studio multiplayer scenarios.

Network names and message shapes live in `src/shared/network/Protocol.luau`. Server request handlers call server validation before effects. The planned action contract uses one request/result/event set, detailed in [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md); do not create remotes ad hoc in gameplay modules.

## Planned module map

The module map is the locked V1 target. M1 implements shared constants, base/session services, a Raid phase-state skeleton, and a temporary greybox with eight base pads. M2 adds the version-1 profile, DataStore session lease, shared creature/economy definitions, online income, and leaderboard values. Capsules, mutation transactions, timed Raids, theft, full UI, analytics integration, and monetization remain unimplemented.

| Module and location | Responsibility and authority | Dependencies / public interface | Required tests |
| --- | --- | --- | --- |
| `ServerBootstrap` — `src/server/Bootstrap.server.luau` | Compose services once and connect Roblox lifecycle entry points. | Starts `SessionService` and `ActionService`; no domain rules. | Bootstrap order, missing dependency fails clearly, remotes bound once. |
| `ActionService` — `src/server/services/ActionService.luau` | Validate the shared request envelope/session, apply transport and action rate limits, cache request results, and dispatch to domain services. It owns no game rules. | Shared protocol, Session, Raid, Base, and domain service interfaces; `start`, `handleRequest`. | Malformed/stale-session requests, replay, rate limits, dispatch failure, and no duplicate effects. |
| `SessionService` — `src/server/services/SessionService.luau` | Own join/leave flow, profile-ready ordering, base ownership, and unload ordering. | `PlayerDataService`, `BaseService`; `start`, `onPlayerAdded`, `onPlayerRemoving`. | Duplicate join/leave, load failure, base cleanup, session-lock conflict. |
| `BaseService` — `src/server/services/BaseService.luau` | Assign one of eight plots, track operational character/base, release plot. | No service dependency; `SessionService` calls `assign`/`release`; exposes `isOperational`, `getForPlayer`, and `setOperational`. | Eight slots, no duplicate assignment, rejoin/reset, operational-ready state. |
| `PlayerDataService` — `src/server/services/PlayerDataService.luau` | Own the validated profile, durable first-Raid participation marker, and completion flag; expose narrow mutations/snapshots. | `ProfileStore`; `load`, `getSnapshot`, `getCreatures`, `creditScrap`, `beginFirstRaidParticipation`, `finalizeFirstRaidParticipation`, `save`, `unload`. | Defaults, bounds, strict schema, marker idempotency/finalization, dirty save, capped credit. |
| `ProfileStore` — `src/server/persistence/ProfileStore.luau` | Server-only DataStore adapter, metadata session lease, serialization, bounded retries. M7 adds backup/quarantine recovery. | Roblox DataStore APIs only; `load`, `save`, `release`. | Transient/exhausted failures, duplicate/expired session, malformed data, shutdown; M7 adds migration/recovery. |
| `EconomyService` — `src/server/services/EconomyService.luau` | Scrap balance, online income, prices, catalyst purchase, slot purchase, and sale transactions. | PlayerData, Creature, `EconomyConfig`; `getSnapshot`, `sell`, `purchaseSlot`, `purchaseCatalyst`. | Exact income, fraction carry online, no offline income, insufficient funds, transaction replay. |
| `CreatureService` — `src/server/services/CreatureService.luau` | Server-owned creature instances, IDs, ownership, capacity and stand/reservation checks. | PlayerData, Base, definitions; `getOwned`, `getCreature`, `add`, `remove`, `transfer`. | Stable unique IDs, capacity, starter rule, ownership invariants, transfer atomicity. |
| `CapsuleService` — `src/server/services/CapsuleService.luau` | Welcome/standard capsule validation, server roll, pity and Welcome ID. | Economy, Creature, PlayerData, `CreatureDefinitions`; `purchase`. | Odds/pity floors, guaranteed Welcome, capacity/funds, replay and server-selected result. |
| `MutationService` — `src/server/services/MutationService.luau` | Tutorial and normal mutation transactions, result choice, one pity counter. | Economy, Creature, PlayerData, `MutationDefinitions`; `tutorial`, `start`, `resolve`. | Costs, catalyst, exact odds, pity, old-form preservation, replay, phase/lock rejection. |
| `RaidService` — `src/server/services/RaidService.luau` | Shared per-server phase clock, Raid IDs, phase events, first-Raid eligibility and scheduled completion boundary. | PlayerData, Base; `getSnapshot`, `start`, `stop`, `beginFirstRaidParticipation`, `finalizeFirstRaidParticipation`. | Exact durations/order, boundary races, joins in every phase, strict grace comparison, marker timing and idempotency. |
| `TheftService` — `src/server/services/TheftService.luau` | Theft attempt/base locks, channel, carry/drop/return/bank and per-Raid limits. | Raid, Base, Creature, PlayerData, Analytics; `begin`, `cancel`, `bank`, `recover`. | All theft race, limit, disconnect, reset, phase-end, replay and transfer-journal cases. |
| `TagService` — `src/server/services/TagService.luau` | Validate Tag, cooldown/immunity/stagger; request a drop/cancel from TheftService. | Raid, Base, Theft; `tag`. | Range, cooldown, immunity, channel cancel, carried drop, zero catalyst reward. |
| `AnalyticsService` — `src/server/services/AnalyticsService.luau` | Emit bounded server-owned domain events through provider-neutral contract. | Domain services and `src/server/analytics/Contracts.luau`; `emit`. | Event schema/allowlist, no raw payload/precise location, no client authority. |
| `MonetizationService` — `src/server/services/MonetizationService.luau` (M11) | Refresh/verify one cosmetic Game Pass entitlement; no gameplay grants. | Roblox MarketplaceService, PlayerData snapshot; `refreshPalettePass`. | API failure, repeated refresh, cosmetic-only result; no product IDs before approved setup. |
| `CreatureDefinitions` — `src/shared/definitions/CreatureDefinitions.luau` | Public immutable species IDs, rarity, and base-income catalog. | No runtime dependency; catalog lookup and ID validation. | Exactly 12 valid species, rarity groups, and income values. |
| `MutationDefinitions` — `src/shared/definitions/MutationDefinitions.luau` | Public immutable themes, forms, tiers, odds, and multipliers. | `CreatureDefinitions` IDs only where needed; catalog lookup and form validation. | Exactly 24 forms, three themes, exact odds/multipliers, no Mythic pity field. |
| `Constants` — `src/shared/config/Constants.luau` | Shared numeric limits and stable enums that are not economy or Raid tuning. | No runtime dependency; readonly values. | Bounds and phase/action enum parity. |
| `EconomyConfig` — `src/shared/config/EconomyConfig.luau` | Public prices, income cadence, sale refund, and slot costs. | `Constants`; readonly config table. | Prices, capacity, and income cadence match the design. |
| `CapsuleConfig` — `src/shared/config/CapsuleConfig.luau` | Public capsule prices, tier weights, and pity floors. | `Constants`, `CreatureDefinitions`; readonly config table. | Weights sum to 1,000; 3/8 pity limits and valid tier pools. |
| `RaidConfig` — `src/shared/config/RaidConfig.luau` | Public phase durations, arrival grace, channel/recovery timing, and limits. | `Constants`; readonly config table. | Eight-minute cycle and all documented timing/limit values. |
| Shared protocol/types — `src/shared/network/Protocol.luau`, `src/shared/types/*` | Names, allowlisted request/result/event schemas, shared IDs/enums. No authority. | No server/client runtime dependencies; payload validators and shared type definitions. | Shape/type/size validators; parity with NETWORK_PROTOCOL.md. |
| `ClientBootstrap` — `src/client/Bootstrap.client.luau` | Start each client controller once and stop them with the client lifecycle. | Client controllers and shared protocol/types; `start`, `stop`. | Startup order, one-time bindings, clean teardown. |
| `HudController` — `src/client/controllers/HudController.luau` | Present Scrap, income, capacity, Raid timer, and next-goal card. Presentation only. | Shared types; server snapshot and domain events; `start`, `renderSnapshot`, `stop`. | Snapshot/event rendering, missed-revision refresh, labels and mobile readability. |
| `InteractionController` — `src/client/controllers/InteractionController.luau` | Contextual prompts and touch/keyboard input; sends allowlisted requests. Presentation/input only. | Shared protocol and replicated remotes; `start`, `setContext`, `requestAction`, `stop`. | Touch/keyboard parity, no client-side authority, target size and invalid-context handling. |
| `RaidPresentationController` — `src/client/controllers/RaidPresentationController.luau` | Render the shared phase, countdown, warning, and raid result cues. Presentation only. | Shared phase types and `RaidPhaseChanged`; `start`, `renderPhase`, `stop`. | Phase ordering, timer resync, missed event recovery, accessible visual alert. |
| `CapsuleMutationController` — `src/client/controllers/CapsuleMutationController.luau` | Present odds, capsule reveal, mutation reveal, and keep/replace/decline choices. Presentation only. | Shared definitions/protocol; server snapshots and action results; `start`, `renderResult`, `stop`. | Odds shown match server data; replay/error responses do not invent outcomes. |
| `CreaturePresentationController` — `src/client/controllers/CreaturePresentationController.luau` | Render stand creatures, rarity/form labels, and inspect details. Presentation only. | Shared definitions; server creature snapshots/events; `start`, `renderCreatures`, `stop`. | Catalog coverage, readable silhouettes/labels, no client-owned mutation or income. |
| `AudioEffectsController` — `src/client/controllers/AudioEffectsController.luau` | Play approved cues and lightweight effects with reduced-effects support. Presentation only. | Shared event types and client settings; `start`, `playCue`, `setReducedEffects`, `stop`. | Cues match domain events, reduced effects, visual equivalents, no gameplay-state writes. |

The module locations are fixed as listed; keep service APIs narrow and do not add a generic framework, repository layer per domain, or client-side domain service. Only the server can commit state. `TheftService` owns dropped-creature recovery because it owns the transfer state machine; `TagService` asks it to cancel/drop an attempt.

## Dependency direction

Clients may depend on shared modules. Server modules may depend on shared modules and server-only services. Shared code must not depend on client or server runtime state. Presentation observes replicated server results; it does not decide outcomes. `BaseService` emits operational readiness without reading Raid state; `RaidService` consumes that signal, so this lifecycle has no service cycle. Other services depend only on listed interfaces; compose them in `ServerBootstrap`.

## Persistence boundary

`src/server/persistence/ProfileStore.luau` stores the exact version-1 profile in one DataStore key and keeps the active session lease in key metadata. The atomic `UpdateAsync` callback validates the existing record, acquires or refreshes the lease, and preserves associated user IDs. `PlayerDataService` validates the full schema before exposing a profile and owns all loaded state. Sequential migrations, backup/quarantine recovery, and transaction journals remain M7 work. Player requests must never contain authoritative saved state; see [DATA_MODEL.md](DATA_MODEL.md) and [SECURITY.md](SECURITY.md).

`src/server/analytics/Contracts.luau` defines a provider-neutral internal event boundary. `src/server/monetization/Contracts.luau` defines the future receipt handler/result boundary. Neither connects to external services or grants products in this phase.

## State and test ownership

[STATE_MACHINES.md](STATE_MACHINES.md) is the source of truth for Raid, theft, mutation, and Welcome participation transitions. [TESTING.md](TESTING.md) maps required tests to domain services, persistence, and Studio. Every gameplay service must have deterministic unit/service tests before its Studio integration scenarios; portable Lune is not multiplayer simulation.

## Foundation smoke path

The tiny DevPing RemoteFunction demonstrates a centralized remote name, strict payload shape, and server-side rejection. It grants no state and is not a gameplay feature. Remove or disable it before public launch if it is no longer useful.
