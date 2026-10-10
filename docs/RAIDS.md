# Raid and theft rules

## Shared raid cycle

Each server instance runs one server-owned cycle. A fresh instance starts with 5 minutes of PEACE. Players who join an existing instance enter its current phase; there is no personal timer.

| Phase | Duration | Rules |
| --- | ---: | --- |
| PEACE | 5:00 | Normal play and purchases. No theft. |
| WARNING | 0:30 | Siren and countdown. Purchases remain available. |
| RAID | 1:30 | Theft and Tag are enabled. Capsule, mutation, sale, and slot-purchase actions are disabled. |
| RESOLUTION | 0:30 | No new theft or purchases. In-flight items return; completed deposits stay transferred. |
| COOLDOWN | 0:30 | Results summary; normal play and purchases resume. |

The cycle is 8 minutes. In a fresh server, Warning starts at 5:00, Raid at 5:30, Resolution at 7:00, Cooldown at 7:30, and the next Peace at 8:00. The next Warning begins at 13:00.

All bases are visible. During Warning, gates open and the siren gives everyone 30 seconds to react. Only RAID permits a new theft attempt. A newly joined player is eligible as soon as their base is assigned; there is no extra spawn shield.

## What can be stolen

- Only a non-starter creature owned by a player still in the server can be targeted.
- Scrap, catalysts, slot upgrades, and mutations are never removed from the victim.
- The starting Mossling instance can never be targeted, sold, or transferred. This permanent starter floor is the single new-player protection rule.
- One owner can lose at most one creature per raid. When a valid pickup channel begins, the server locks that owner's base until the attempt is canceled, the creature is returned, or the bank completes. Another thief cannot start from that owner while the lock is held.
- Each thief may attempt up to two different creatures per raid, but may bank only one. This allows one retry after a defended attempt without enabling repeated harassment.
- A thief needs one free slot. That slot is reserved when the theft attempt begins.
- A creature can be attempted at most once per raid. A failed or interrupted attempt closes that creature for the rest of the raid.
- The thief can carry only one creature. The owner retains ownership until the thief completes the bank interaction.

## Theft sequence

1. During RAID, the thief enters another player's base and holds the contextual Steal button while within 7 studs of a valid creature.
2. The thief must remain still for 2.5 seconds. Moving out of range, being Tagged, a phase boundary, or either player's disconnect cancels the attempt.
3. On completion, the creature leaves its stand and becomes a reserved carried item. It remains owned by the original player; the thief cannot earn its income or mutate it in transit.
4. The carrier moves at 80% of normal walk speed and cannot jump, sprint, or use tools. Only the home pad in the thief's base can complete the transfer.
5. On that pad, a 1-second stationary hold completes the bank. The server commits ownership only if this hold completes strictly before RAID ends.

The pickup and bank use server-measured distance and time. The two holds plus a 120–180 stud route create an approximately 13–18 second unchallenged run.

## Tag defense

Tag is the only defense action. During RAID, any player may use it when a thief is channeling or carrying within 7 studs.

- One successful Tag cancels the channel or drops the carried creature.
- A dropped creature can be recovered by its original owner with a 1-second hold within 5 seconds. If it is not recovered, it returns to the original owner automatically.
- Each defender has a 6-second Tag cooldown. A thief who was successfully Tagged has 5 seconds of immunity from every Tag, preventing a group from chaining stuns.
- A Tag causes a 1-second stagger. It deals no damage and has no effect outside RAID.
- A Tag earns its user one chosen catalyst for the raid only if it actually cancels a channel or forces a drop. An attempt that misses gives no reward.

An attacker who is Tagged has used one of their two attempts. They may try a different creature if one attempt remains and the Raid is still active. They cannot target the same creature again that raid. A successful bank ends their attempts for the raid.

## Ownership, persistence, and edge cases

| Situation | Deterministic result |
| --- | --- |
| Two thieves request the same creature | The server grants one target lock to the first valid request; the other request is rejected. |
| Two thieves target different creatures from one owner | The first valid channel takes the owner's base lock, including while channeling or while a dropped item is awaiting return. The owner's one-loss limit is committed on bank. |
| Thief's base is full | The attempt is rejected before starting; no slot is reserved and no attempt is consumed. |
| Victim has a full base | It does not prevent theft; the transfer frees a slot for the victim. |
| Mutation requested twice | One server request ID can consume at most one catalyst and one Scrap cost. A reserved creature cannot be mutated. |
| Duplicate or replayed request | Idempotency key and server-side state allow one action only; replay is rejected without a second charge or transfer. |
| Theft is still channeling/carrying at RAID end | It is canceled and the creature returns to its original stand. |
| Bank and phase end occur together | A server timestamp strictly earlier than the end commits; equal or later returns the creature. |
| Thief disconnects, resets, or respawns while carrying | The creature returns to the owner. The thief's raid attempt remains spent. |
| Owner disconnects during a transfer | The transfer is canceled and the creature remains with the owner. Offline bases cannot be targeted. |
| Owner resets while online | The base remains eligible; reset is not a protection mechanic. |
| Server shuts down during a transfer | Unbanked reservations reconcile back to the original owner; a banked transfer is committed once using an idempotent journal. |
| Player joins during any phase | Base is assigned immediately and the player uses the current phase. The protected starter remains safe; no personal raid reset occurs. |
| Latency or malformed remote payload | Server phase, ownership, proximity, capacity, rate limits, and request IDs decide the outcome. Client claims have no authority. |

Income continues during raids and is never stolen. A completed bank moves the creature and its future income permanently; the former owner keeps all Scrap already earned. No currency is dropped or lost.

## Exploit-sensitive boundaries

The server owns phase transitions, Scrap, ownership, target locks, carrier state, Tag cooldowns, pity/rewards, and transfer commits. Client prompts are presentation only. Every action checks player identity, phase, ownership, creature instance ID, distance, capacity, cooldown, request rate, and idempotency. A transfer is a single atomic state change; failed persistence must roll back or reconcile without duplication.
