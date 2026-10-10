# Security rules

The server is authoritative for currency, rewards, creatures, rarity, mutations, inventory, upgrades, raids, ownership, persistence, entitlements, and purchase receipts. Replicated modules and client state are inspectable and modifiable by players.

## Request validation

Treat every remote as hostile input. Validate the calling player identity and current state; ownership; proximity using server-observed positions; phase; cooldown and request frequency; IDs and item existence; capacity; permissions; payload type, size, and shape; duplicate/replay request identifiers; and whether the requested transition is legal. Apply rate limits before expensive work. Reject safely and log useful diagnostics without echoing sensitive data.

Do not accept client claims about amount, reward earned, ownership, rarity, mutation result, raid success, save state, entitlement, or receipt fulfillment. Derive these on the server from trusted server state and verified Roblox purchase callbacks.

Centralize remote declarations and message shapes in `src/shared/network/Protocol.luau`; keep handler validation in server code. A typed payload is a development aid, not a security boundary. `DevPing` is a schema-validation smoke only and must not grow into a debug authority channel.

## Persistence safety

Introduce saved state only behind server-only persistence modules. Include a schema version and sequential, deterministic migrations. Validate loaded data before use, bound numeric values and collection sizes, and preserve a safe backup or quarantine recoverable corrupt records instead of overwriting them with defaults. Use session locking or equivalent duplicate-session protection. Save with bounded retries and backoff; distinguish transient service errors from invalid data. Never report a save as successful until the store confirms it. Keep in-memory defaults separate from persisted schema and make shutdown saves best-effort without depending on shutdown as the only save point.

## Purchases

Process Developer Product receipts idempotently on the server, grant only after a verified receipt, and record receipt identifiers to prevent duplicate grants. Validate Game Pass ownership server-side. Never grant from client UI callbacks. Keep product IDs in server configuration and test fulfillment, retry, duplicate receipt, and failure paths before adding products.
