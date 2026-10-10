# Architecture

V1 uses one server-authoritative service layer, a small shared definitions/protocol layer, and client controllers for input and display. This is a locked implementation plan, not permission to implement gameplay during the readiness phase.

## Source of truth and runtime mapping

The filesystem is authoritative. Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to `ServerScriptService.Server`, and `src/client` to `StarterPlayer.StarterPlayerScripts.Client`. Wally-generated development packages are mapped under `ServerStorage.DevPackages`, and the TestEZ spec tree is mapped to `ServerStorage.FoundationTests`; generated package sources and place builds are ignored by Git. `default.project.json` is the single project map.

## Boundaries

- `shared`: protocol types, constants, deterministic utilities, and non-secret configuration. Treat replicated code and data as public.
- `server`: service orchestration, validation, ownership, persistence, economy, rewards, purchase fulfillment, and all authoritative decisions.
- `client`: input, presentation, effects, and requests. A client response or local state never proves ownership or entitlement.
- `tests`: portable Lune tests plus Roblox-native TestEZ and Studio multiplayer scenarios.

Network names and message shapes live in `src/shared/network/Protocol.luau`. Server request handlers call server validation before effects. The planned action contract uses one request/result/event set, detailed in [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md); do not create remotes ad hoc in gameplay modules.

## Planned module map

All rows below describe future modules. The repository currently has only the foundation bootstrap, DevPing smoke, and persistence/analytics/monetization contracts; no gameplay services or controllers are implemented.

| Module and location | Responsibility and authority | Dependencies / public interface | Required tests |
| --- | --- | --- | --- |
| `ServerBootstrap` — `src/server/Bootstrap.server.luau` | Compose services once and connect Roblox lifecycle/network entry points. | Starts `SessionService`; no domain rules. | Bootstrap order, missing dependency fails clearly, remotes bound once. |
| `SessionService` — `src/server/services/SessionService.luau` | Own join/leave flow, session ID, load/ready/unload ordering. | `PlayerDataService`, `BaseService`; `start`, `onPlayerAdded`, `onPlayerRemoving`. | Duplicate join/leave, load failure, base cleanup, session-lock conflict. |
| `BaseService` — `src/server/services/BaseService.luau` | Assign one of eight plots, observe operational character/base, release plot. | No service dependency; `SessionService` calls `assign`/`release`; exposes `isOperational`, `getBase`, and operational-ready signal. | Eight slots, no duplicate assignment, rejoin/reset, operational-ready event. |
| `PlayerDataService` — `src/server/services/PlayerDataService.luau` | Own validated in-memory profile and expose narrow mutations/snapshots. | `ProfileStore`; `load`, `getSnapshot`, `commit`, `unload`. | Defaults, bounds, schema migration, dirty save, marker normalization, replay safety. |
| `ProfileStore` — `src/server/persistence/ProfileStore.luau` | Server-only DataStore adapter, session lock, serialization, retries, backup/quarantine. | Roblox DataStore APIs only; `load`, `save`, `release`. | Transient/exhausted failures, duplicate session, corruption, shutdown, migration. |
| `EconomyService` — `src/server/services/EconomyService.luau` | Scrap balance, online income, prices, catalyst purchase, slot purchase, and sale transactions. | PlayerData, Creature, `EconomyConfig`; `getSnapshot`, `sell`, `purchaseSlot`, `purchaseCatalyst`. | Exact income, fraction carry online, no offline income, insufficient funds, transaction replay. |
| `CreatureService` — `src/server/services/CreatureService.luau` | Server-owned creature instances, IDs, ownership, capacity and stand/reservation checks. | PlayerData, Base, definitions; `getOwned`, `getCreature`, `add`, `remove`, `transfer`. | Stable unique IDs, capacity, starter rule, ownership invariants, transfer atomicity. |
| `CapsuleService` — `src/server/services/CapsuleService.luau` | Welcome/standard capsule validation, server roll, pity and Welcome ID. | Economy, Creature, PlayerData, `CreatureDefinitions`; `purchase`. | Odds/pity floors, guaranteed Welcome, capacity/funds, replay and server-selected result. |
| `MutationService` — `src/server/services/MutationService.luau` | Tutorial and normal mutation transactions, result choice, one pity counter. | Economy, Creature, PlayerData, `MutationDefinitions`; `tutorial`, `start`, `resolve`. | Costs, catalyst, exact odds, pity, old-form preservation, replay, phase/lock rejection. |
| `RaidService` — `src/server/services/RaidService.luau` | Shared per-server phase clock, Raid IDs, phase events, first-Raid participant timestamps. | PlayerData, Base; `getSnapshot`, `start`, `stop`, participant marker transitions. | Exact durations/order, boundary races, joins in every phase, marker timing and idempotency. |
| `TheftService` — `src/server/services/TheftService.luau` | Theft attempt/base locks, channel, carry/drop/return/bank and per-Raid limits. | Raid, Base, Creature, PlayerData, Analytics; `begin`, `cancel`, `bank`, `recover`. | All theft race, limit, disconnect, reset, phase-end, replay and transfer-journal cases. |
| `TagService` — `src/server/services/TagService.luau` | Validate Tag, cooldown/immunity/stagger; request a drop/cancel from TheftService. | Raid, Base, Theft; `tag`. | Range, cooldown, immunity, channel cancel, carried drop, zero catalyst reward. |
| `AnalyticsService` — `src/server/services/AnalyticsService.luau` | Emit bounded server-owned domain events through provider-neutral contract. | Domain services and `src/server/analytics/Contracts.luau`; `emit`. | Event schema/allowlist, no raw payload/precise location, no client authority. |
| `MonetizationService` — `src/server/services/MonetizationService.luau` (M11) | Refresh/verify one cosmetic Game Pass entitlement; no gameplay grants. | Roblox MarketplaceService, PlayerData snapshot; `refreshPalettePass`. | API failure, repeated refresh, cosmetic-only result; no product IDs before approved setup. |
| Shared definitions/config — `src/shared/definitions/*`, `src/shared/config/*` | Immutable species/forms, prices/odds, Raid timing, capacities, and numeric constants. Replicated and public. | No runtime services; typed readonly tables. | Catalog completeness, bounds, exact odds and configuration invariants. |
| Shared protocol/types — `src/shared/network/Protocol.luau`, `src/shared/types/*` | Names, allowlisted request/result/event schemas, shared IDs/enums. No authority. | No server/client runtime dependencies. | Shape/type/size validators; parity with NETWORK_PROTOCOL.md. |
| Client controllers — `src/client/controllers/*` | HUD, contextual interaction/touch input, Raid presentation, capsule/mutation panels, creature display, audio/effects. Presentation only. | Shared types/protocol; server snapshots and DomainEvents. | Input shape, event rendering, missed revision resync, accessibility and Studio client smoke. |

The module locations are fixed as listed; keep service APIs narrow and do not add a generic framework, repository layer per domain, or client-side domain service. Only the server can commit state. `TheftService` owns dropped-creature recovery because it owns the transfer state machine; `TagService` asks it to cancel/drop an attempt.

## Dependency direction

Clients may depend on shared modules. Server modules may depend on shared modules and server-only services. Shared code must not depend on client or server runtime state. Presentation observes replicated server results; it does not decide outcomes. `BaseService` emits operational readiness without reading Raid state; `RaidService` consumes that signal, so this lifecycle has no service cycle. Other services depend only on listed interfaces; compose them in `ServerBootstrap`.

## Persistence boundary

`src/server/persistence/Contracts.luau` defines a server-only versioned profile/store contract; it intentionally does not create a save schema or DataStore implementation. Player requests must never contain authoritative saved state. The exact planned V1 fields/defaults and migration policy are in [DATA_MODEL.md](DATA_MODEL.md); see [SECURITY.md](SECURITY.md) for server validation and corruption safety.

`src/server/analytics/Contracts.luau` defines a provider-neutral internal event boundary. `src/server/monetization/Contracts.luau` defines the future receipt handler/result boundary. Neither connects to external services or grants products in this phase.

## State and test ownership

[STATE_MACHINES.md](STATE_MACHINES.md) is the source of truth for Raid, theft, mutation, and Welcome participation transitions. [TESTING.md](TESTING.md) maps required tests to domain services, persistence, and Studio. Every gameplay service must have deterministic unit/service tests before its Studio integration scenarios; portable Lune is not multiplayer simulation.

## Foundation smoke path

The tiny DevPing RemoteFunction demonstrates a centralized remote name, strict payload shape, and server-side rejection. It grants no state and is not a gameplay feature. Remove or disable it before public launch if it is no longer useful.
