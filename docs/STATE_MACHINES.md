# V1 state machines

All states, transition timestamps, ownership, and outcomes below are server-owned. Clients may request transitions and render the resulting state; client animation, clocks, and claims do not decide outcomes.

## Shared Raid phase

```text
PEACE (5:00) → WARNING (0:30) → RAID (1:30) → RESOLUTION (0:30)
             → COOLDOWN (0:30) → PEACE
```

- A new server starts PEACE at its server start time; the cycle repeats every 8 minutes. Players joining inherit the current phase.
- Only the next state in the sequence is allowed. No player request starts, skips, pauses, or extends a phase.
- WARNING opens gates and announces the countdown; only RAID allows new theft and Tag. RESOLUTION returns unfinished transfers and blocks purchases/new interactions; COOLDOWN resumes normal economy actions.
- At RAID-to-RESOLUTION, stop new theft, bank, Tag, and recovery actions; resolve all in-flight reservations deterministically. The first-Raid completion timestamp is the following RESOLUTION-to-COOLDOWN boundary.
- A disconnect or character reset never changes the shared clock. The server resolves pending theft; reset does not refresh same-Raid arrival grace.

## Theft lifecycle

```text
AVAILABLE → CHANNELING → CARRIED → BANKED
                 │            └→ DROPPED → RETURNED
                 ├→ RETURNED
                 └→ (server cancellation) RETURNED
```

| State | Entry and allowed next steps | Disconnect, reset, and phase boundary |
| --- | --- | --- |
| `AVAILABLE` | Eligible creature has no attempt/owner lock. Valid `BeginTheft` creates one attempt and locks that owner's base and the creature. | No reservation to clean up. |
| `CHANNELING` | Thief holds still in range for 2.5 seconds. Success reserves the creature and enters `CARRIED`; cancel, movement, Tag, or invalidation returns it. | Either player disconnecting/resetting or RAID ending returns it; attempt and creature-attempt are spent. |
| `CARRIED` | Creature remains owned by victim; thief is slowed and can request a server-timed bank hold at home pad. Tag enters `DROPPED`. | Thief/owner disconnect, thief reset, or RAID end returns it to owner; no bank after RAID end. |
| `DROPPED` | One-second owner recovery within 5 seconds enters `RETURNED`; timeout returns automatically. The owner base lock remains held until resolution. | Disconnect, reset, or RAID end returns it; no duplicate copy. |
| `RETURNED` | Terminal for this attempt; release reservation and locks. Creature remains/returns to owner. | Idempotent cleanup; never reopens this creature's attempt in the same Raid. |
| `BANKED` | Terminal after server validates the full hold strictly before RAID end and atomically commits ownership. | Idempotent journal reconciliation preserves exactly one owner; thief can bank only once this Raid. |

No transition may assign ownership while the creature is merely `CHANNELING`, `CARRIED`, or `DROPPED`. One owner can lose at most one creature per Raid; one thief can attempt two different creatures and bank one. Starter and currently protected Welcome creature are never `AVAILABLE` targets.

## Mutation transaction

```text
IDLE → ROLLING → REVEALED → KEEP_CURRENT / REPLACE / DECLINE → IDLE
```

- `StartMutation` is accepted only in PEACE, WARNING, or COOLDOWN for an owned, unreserved creature, with matching catalyst and 100 Scrap. Charge, server roll, and pity update are one transaction; server records one pending result.
- The one-time free tutorial mutation must be completed before a normal mutation can start. It equips one uniformly selected Common form from the player's chosen theme to the exact starter ID without changing Scrap or pity.
- `ROLLING` is the short reveal presentation. The result is already fixed server-side; skipping the animation changes no outcome.
- `REVEALED` accepts one choice. `KEEP_CURRENT` and `DECLINE` both leave the old form equipped and do not refund; `REPLACE` equips the result. Only an equipped form is added to Codex.
- A second mutation is forbidden until the first returns to `IDLE`. Replayed starts or choices cannot charge twice or replace twice.
- If the player disconnects or a forbidden phase begins while a result is pending, discard the offer, keep the active form, keep the cost/pity result already committed, and return to `IDLE`. Do not persist a pending roll as ownership.
- Reset/respawn has no effect on server mutation state. Invalid phase, missing catalyst, insufficient Scrap, or reserved creature leaves `IDLE` and charges nothing.

## Welcome protection and first-Raid participation

```text
PROTECTED → PARTICIPATING_IN_FIRST_RAID → EXPIRED
      └──── (late grace through RAID end) remains PROTECTED for a later Raid
```

- `PROTECTED` means `welcomeCreatureId` is set and `hasCompletedFirstRaid` is false. The starter Mossling has separate permanent protection.
- PEACE/WARNING cannot consume protection. At RAID start, immediately mark each player already present whose `hasCompletedFirstRaid` is false and who has no participation marker; character/base initialization does not defer this marker. The write is idempotent and never replaces a marker.
- A player joining during RAID starts one 15-second arrival grace when both character and base are operational. If that original timestamp expires strictly before RAID-to-RESOLUTION, transition to participation then and persist the current Raid ID and scheduled RESOLUTION-to-COOLDOWN timestamp. Otherwise that Raid does not consume protection.
- Respawn, reset, disconnect, and rejoin cannot restart grace or erase participation. Rejoining before the marker deadline reuses the same marker. A marker is never created by PEACE/WARNING or a late join whose grace reaches/passes RAID end.
- At the marker's scheduled RESOLUTION-to-COOLDOWN boundary, set `hasCompletedFirstRaid = true`, clear the matching marker, and transition to `EXPIRED`. `RaidService` owns eligibility and the shared boundary; `PlayerDataService` owns the profile write. If the player is offline, profile load at or after the timestamp performs the same idempotent transition before gameplay. Disconnect after participation does not preserve protection.
- If no Welcome creature exists when the first Raid completes, the completion still stands; a Welcome Capsule claimed later is not protected by a completed first Raid. The protection marker never affects another creature.

## Ownership and failure rule

The server owns every transition. Validate an action against current state and phase at commit time. A persistence failure must either roll back before acknowledgement or reconcile through an idempotent record; never expose duplicate ownership, refund after a committed transfer, or let a client force a terminal state. See [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md) for request contracts and [DATA_MODEL.md](DATA_MODEL.md) for durable fields.
