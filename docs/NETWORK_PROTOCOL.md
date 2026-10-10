# Planned network protocol

This is a contract for later gameplay implementation. It does not create gameplay remotes. The existing `DevPing` remains a foundation-only smoke and is not part of this protocol.

## Envelope and rules

Use one client-to-server `ActionRequest` RemoteEvent and server-to-client `ActionResult` and `DomainEvent` RemoteEvents, declared centrally in `src/shared/network/Protocol.luau`. Do not add per-feature remotes.

```text
ActionRequest  { sessionId, requestId, action, payload }
ActionResult   { sessionId, requestId, ok, code?, data?, profileRevision? }
DomainEvent    { event, revision, serverTimeUnix, data }
```

The server issues a fresh opaque `sessionId` for each loaded player session. `requestId` is a client-generated bounded UUID/string, unique within that session. The server validates exact allowlisted keys, types, maximum lengths, enum values, and payload size; derives Player identity from the RemoteEvent; and returns the same cached result for a repeated `(userId, sessionId, requestId)`. Requests from an old session are rejected. Domain events contain server-derived state only. Client timestamps, prices, rewards, positions, ownership, rarity, phase, pity, and entitlement claims are never authoritative.

Apply a per-player token bucket of 10 requests/second with burst 20 before expensive work, plus the action-specific throttles below. Domain limits (for example Tag cooldown and two theft attempts) are separate from transport rate limits. Rejections do not partially charge, grant, or transfer. Use persistent idempotency/journaling for saved ownership and purchase transactions that must survive server recovery.

Phase shorthand: **Economy** means PEACE, WARNING, or COOLDOWN. All phase decisions are read from the server RaidService. Interactions also require server-observed proximity, operational character/base, ownership, capacity, and current transaction state.

## Action contracts

| Action / direction | Payload | Success result / server event | Validation, phase, throttle, and idempotency |
| --- | --- | --- | --- |
| `PurchaseCapsule` C→S | `{kind: "Welcome"\|"Standard"}` | Result `{creature, scrapBalance, pity}`; `CreatureAdded` domain event. | Economy phases only; kiosk range; capacity and 120 Scrap; Welcome available only if `welcomeCreatureId == nil`; server rolls species and standard pity; 2/sec; request replay returns same result and cannot charge/grant twice. |
| `SellCreature` C→S | `{creatureId}` | `{creatureId, refund: 60, scrapBalance}`; `CreatureRemoved`, `ScrapChanged`. | Economy phases only; kiosk range; owned non-starter creature not reserved, carried, or in mutation; 2/sec; one commit per request ID. |
| `PurchaseSlot` C→S | `{targetCapacity: 3\|4}` | `{slotCapacity, scrapBalance}`; `CapacityChanged`. | Economy phases only; kiosk range; exact next upgrade, required creature count, price 350/1,200, Slot 4 first-Raid-complete gate; 2/sec; same request cannot charge twice. |
| `PurchaseCatalyst` C→S | `{themeId}` | `{themeId, count, scrapBalance}`; `CatalystChanged`, `ScrapChanged`. | Economy phases only; catalyst kiosk range; server maps theme to its matching item and charges 60 Scrap for one; 2/sec; request replay cannot double charge/grant. |
| `GetSnapshot` C→S | `{}` | `{phase, scrap, creatures, slotCapacity, catalysts, pity, codex, tutorialCompleted}` plus profile/phase revisions; `PlayerSnapshot`. | Any phase; server returns the caller's safe presentation snapshot and current shared phase; 1 request/2 sec; read-only and idempotent. Use after a missed DomainEvent revision; never include other players' private profile data. |
| `StartMutation` C→S | `{creatureId, themeId}` | `{transactionId, revealedFormId, oddsSnapshot}`; `MutationRevealed`. | Economy phases only; station range; owned, unreserved creature; matching catalyst and 100 Scrap; no other pending mutation; server rolls and updates pity at start; 1/3 sec; request replay returns same transaction. |
| `ResolveMutation` C→S | `{transactionId, choice: "KeepCurrent"\|"Replace"\|"Decline"}` | `{activeFormId?, outcome}`; optional `MutationApplied`, and `CodexChanged` only on equip. | Economy phases only; exact pending transaction; keep/decline preserves current form, replace equips revealed form; no refund; one resolution only; choice throttled to 2/sec. Unresolved offer is discarded at a forbidden phase boundary or disconnect, without refund or changing current form. |
| `CompleteTutorialMutation` C→S | `{creatureId, themeId}` | `{themeId, formId, tutorialCompleted: true}`; `MutationApplied`, `TutorialCompleted`. | Economy phases only; owned starter at tutorial station; `tutorialCompleted == false`; server guarantees a Common form of chosen theme, atomically grants/consumes the free catalyst and marks complete; 1 request total, idempotent. |
| `BeginTheft` C→S | `{targetCreatureId}` | `{attemptId, targetUserId, channelEndsAt}`; `TheftStateChanged`. | RAID only; server checks 7-stud range, target eligibility, both players/base operational, neither arrival grace, starter/Welcome protection, owner/base lock, free reserved slot, per-creature attempt, two-attempt and one-loss limits; 1/sec; request idempotent. |
| `CancelTheft` C→S | `{attemptId}` | `{attemptId, state: "Returned"}`; `TheftStateChanged`. | RAID only for player cancellation; caller must own active attempt and be CHANNELING. Server-side cancellation also handles disconnect/reset/phase boundaries. Release locks, close attempted creature for this Raid, and keep thief attempt spent; duplicate cancellation is harmless. |
| `BankTheft` C→S | `{attemptId, stage: "Begin"\|"Complete", catalystThemeId?}` | Begin `{holdStartedAt}`; complete `{attemptId, creatureId, catalystThemeId}`; `TheftBanked`, `CreatureChanged`, `CatalystChanged`. | RAID only. Server checks carrier, home pad, 1-second stationary hold, reserved slot, and server timestamp strictly before RAID end. The client supplies no time. A valid theme is required on Complete; the server grants that chosen catalyst only after a successful bank, at most once per thief per Raid. Begin/complete are scoped to one attempt and request IDs; bank commits ownership once. |
| `Tag` C→S | `{targetUserId}` | `{success, result: "Cancelled"\|"Dropped"\|"Miss"}`; `TagResolved`, optional `TheftStateChanged`. | RAID only; valid target is channeling/carrying thief within 7 studs; server enforces 6-second defender cooldown, 5-second Tagged-thief immunity and 1-second stagger. No catalyst reward. Replays do not apply a second Tag; domain cooldown is authoritative. |
| `RecoverDroppedCreature` C→S | `{attemptId}` | `{attemptId, recovered: boolean}`; `TheftStateChanged`. | RAID only; original owner within 5 studs and within the 5-second recovery window; server measures a 1-second stationary hold. One recovery; otherwise automatic return. Request IDs are idempotent. |
| `RefreshCosmeticEntitlement` C→S (future M11) | `{}` | `{palettePassOwned: boolean, refreshedAt}`; `EntitlementChanged`. | Any phase; server calls the Roblox ownership API and does not grant gameplay state. At most once per 30 seconds per player; failures return a retryable service error and never treat client prompt success as ownership. This remains a future cosmetic-only action. |

## Server-originated domain events

`RaidPhaseChanged` includes phase, phase start/end server times, and Raid ID. `PlayerSnapshot`, `ScrapChanged`, `CreatureAdded/Removed/Changed`, `CatalystChanged`, `CapacityChanged`, `MutationRevealed/Applied`, `TheftStateChanged`, `TagResolved`, `TutorialCompleted`, `CodexChanged`, and future `EntitlementChanged` contain only the minimum presentation state needed by clients. Events are notifications, not authority: clients render them and request a fresh server snapshot after a missed revision. Do not broadcast private profile data or precise base coordinates in a global event.

## Error codes

Use a stable small enum: `InvalidRequest`, `RateLimited`, `WrongPhase`, `OutOfRange`, `NotOwner`, `InsufficientScrap`, `InsufficientCatalyst`, `CapacityFull`, `Locked`, `AlreadyClaimed`, `Expired`, `Unavailable`, `Conflict`, and `ServiceUnavailable`. Include no raw stack traces or sensitive persistence details. See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership and [TESTING.md](TESTING.md) for rejection/replay coverage.
