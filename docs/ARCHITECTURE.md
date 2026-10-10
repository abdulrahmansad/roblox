# Architecture

## Source of truth and runtime mapping

The filesystem is authoritative. Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to `ServerScriptService.Server`, and `src/client` to `StarterPlayer.StarterPlayerScripts.Client`. Wally-generated development packages are mapped under `ServerStorage.DevPackages`, and the TestEZ spec tree is mapped to `ServerStorage.FoundationTests`; generated package sources and place builds are ignored by Git. `default.project.json` is the single project map.

## Boundaries

- `shared`: protocol types, constants, deterministic utilities, and non-secret configuration. Treat replicated code and data as public.
- `server`: service orchestration, validation, ownership, persistence, economy, rewards, purchase fulfillment, and all authoritative decisions.
- `client`: input, presentation, effects, and requests. A client response or local state never proves ownership or entitlement.
- `tests`: portable Lune tests plus Roblox-native TestEZ and Studio multiplayer scenarios.

Network names and message shapes live in `src/shared/network/Protocol.luau`. Server request handlers call server validation before effects. Keep the network layer small; add a remote only for a specific reviewed use case.

## Dependency direction

Clients may depend on shared modules. Server modules may depend on shared modules and server-only services. Shared code must not depend on client or server runtime state. Presentation observes replicated server results; it does not decide outcomes.

## Persistence boundary

`src/server/persistence/Contracts.luau` defines a server-only versioned profile/store contract; it intentionally does not create a save schema or DataStore implementation. Player requests must never contain authoritative saved state. See `SECURITY.md` for versioning, migration, retries, session locking, and corruption policy.

`src/server/analytics/Contracts.luau` defines a provider-neutral internal event boundary. `src/server/monetization/Contracts.luau` defines the future receipt handler/result boundary. Neither connects to external services or grants products in this phase.

## Foundation smoke path

The tiny DevPing RemoteFunction demonstrates a centralized remote name, strict payload shape, and server-side rejection. It grants no state and is not a gameplay feature. Remove or disable it before public launch if it is no longer useful.
