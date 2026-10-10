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

All bases are visible. During Warning, gates open and the siren gives everyone 30 seconds to react. Only RAID permits a new theft attempt.

### Arrival grace for players joining during RAID

A player who joins while the shared phase is RAID receives 15 seconds of server-owned arrival grace, starting when both their character and assigned base are operational. Until the timestamp expires, that player's base cannot be targeted and that player cannot initiate a theft. The grace ends at the earlier of its 15-second expiry or the end of the current RAID; it does not change the shared phase timer or continue into a later RAID. Joining during PEACE or WARNING gives no special grace.

The server records the original grace timestamp per user and current Raid ID. A respawn, reset, disconnect, or rejoin to the same server during that Raid reuses the original timestamp and never refreshes the grace. The server checks this timestamp for both target eligibility and theft initiation; client clocks and client claims do not affect it.

## What can be stolen

- Only a non-starter creature owned by a player still in the server can be targeted.
- Scrap, catalysts, slot upgrades, and mutations are never removed from the victim.
- The starting Mossling instance can never be targeted, sold, or transferred. The specific creature awarded by the Welcome Capsule cannot be targeted until the owner's first completed Raid; all other creatures remain eligible under the normal raid rules.
- One owner can lose at most one creature per raid. When a valid pickup channel begins, the server locks that owner's base until the attempt is canceled, the creature is returned, or the bank completes. Another thief cannot start from that owner while the lock is held.
- Each thief may attempt up to two different creatures per raid, but may bank only one. This allows one retry after a defended attempt without enabling repeated harassment.
- A thief needs one free slot. That slot is reserved when the theft attempt begins.
- A creature can be attempted at most once per raid. A failed or interrupted attempt closes that creature for the rest of the raid.
- The thief can carry only one creature. The owner retains ownership until the thief completes the bank interaction.

The player's first Raid is complete at the shared transition from RESOLUTION to COOLDOWN, after unfinished transfers have returned. A Raid counts as a player's first only if their character and base were operational during that RAID and they are connected when it completes. Welcome protection ends at that boundary. If the player is disconnected at the boundary, keep `hasCompletedFirstRaid = false` and the Welcome creature protected; rejoining before that boundary can still complete the Raid if they are operational and connected when it occurs. Protection is tied to the Welcome Capsule creature's unique ID; it never protects Scrap or another creature. The permanently protected starter rule remains separate.

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
- A Tag awards no catalyst, whether it succeeds or misses. Preventing the creature loss is the defense reward.

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
| Player joins during RAID | Base and character become operational; the server starts a 15-second grace that blocks targeting their base and their own theft attempts. The shared timer does not reset. |
| Player joins during PEACE or WARNING | Base is assigned and the shared phase is inherited; no special arrival grace is granted. |
| Player respawns, resets, or rejoins during the same RAID | The server reuses the original user/Raid-ID grace timestamp; it cannot refresh. |
| Player is disconnected at their first Raid completion boundary | Persist `hasCompletedFirstRaid = false` and their `welcomeCreatureId`; the Welcome creature stays protected on return. |
| Player's first Raid reaches COOLDOWN | After RESOLUTION, mark the connected participant's first Raid complete and end protection for the matching Welcome creature. |
| Latency or malformed remote payload | Server phase, ownership, proximity, capacity, rate limits, and request IDs decide the outcome. Client claims have no authority. |

Income continues during raids and is never stolen. A completed bank moves the creature and its future income permanently; the former owner keeps all Scrap already earned. No currency is dropped or lost.

## Exploit-sensitive boundaries

The server owns phase transitions, Scrap, ownership, target locks, carrier state, Tag cooldowns, arrival-grace timestamps, Welcome protection state, pity/rewards, and transfer commits. Client prompts are presentation only. Every action checks player identity, phase, ownership, creature instance ID, distance, capacity, cooldown, request rate, grace eligibility, and idempotency. A transfer is a single atomic state change; failed persistence must roll back or reconcile without duplication. A successful theft deposit grants its thief one chosen catalyst if they have not already earned a catalyst that Raid; Tag never awards one.
