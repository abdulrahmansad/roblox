# Oddlings: Mutation Run — locked MVP design

## Phase and pitch

This is the approved game design for the first playable release. It is a planning document; it does not authorize gameplay implementation.

**V1 DESIGN FROZEN.** This document and its linked planning documents are the approved implementation specification. Any scope change requires a new explicit design decision.

Oddlings: Mutation Run is a small, eight-player Roblox game about collecting strange creatures, mutating them into showpiece forms, earning Scrap, and making a risky run into another player's base during short, predictable raids.

The promise is simple: build a creature collection that is visibly yours, then decide whether to improve it or risk a raid for someone else's.

## Core loop

Acquire a creature → mutate it → earn Scrap automatically → choose between another creature, a mutation, or a slot → watch the raid warning → steal, defend, or help intercept → keep the result and plan for the next raid.

Income is automatic while online. There is no manual collection, offline income, rebirth, or second main currency.

## Design pillars

1. A new player can explain the goal after one sentence and the first guided mutation.
2. The first capsule is reachable in about 90 seconds and the first raid begins in the first session.
3. Other players create stories through theft and interception; combat is limited to one short Tag action.
4. Collection value is visible from outside a base; the permanent starter and temporary Welcome protection through the first participated Raid keep early losses bounded.
5. The complete gameplay progression is free. Paid content changes appearance only.
6. The MVP uses a small set of reusable creature rigs and mutation recipes.

## Locked scope

| Content or system | MVP count |
| --- | ---: |
| Server size | 8 players |
| Currency | 1: Scrap |
| Catalyst item types | 3 |
| Base creature species | 12 |
| Mutation forms | 24 |
| Mutation themes | 3 |
| Starting creature slots | 2 |
| Maximum creature slots | 4 |
| Permanent slot upgrades | 2 |
| Map | 1 |
| Functional map zones | 3 |
| Raid types | 1 |
| Defense actions | 1: Tag |
| Launch Robux products planned | 1 cosmetic Game Pass |

Creature and mutation details are in [CREATURES.md](CREATURES.md) and [MUTATIONS.md](MUTATIONS.md). Raid rules are in [RAIDS.md](RAIDS.md). Economy and monetization are in [ECONOMY.md](ECONOMY.md) and [MONETIZATION.md](MONETIZATION.md). First-session flow is in [PLAYER_FLOW.md](PLAYER_FLOW.md). The complete scope and milestones are in [MVP.md](MVP.md).

## Base and social read

Each player receives one compact 22 by 18 stud base on the perimeter ring. It begins with two creature stands and can grow to four. Creatures remain on their stands; they do not follow players. Other players can walk up and inspect a creature's species, base rarity, mutation, and current Scrap per minute. Bases are not private during a raid, and no general safe zone prevents a Tag.

The map has three functional zones within one approximately 180 by 180 stud footprint:

1. **Base ring:** eight compact, visible plots around the edge.
2. **Commons:** the capsule kiosk, catalyst kiosk, and an open viewing circle.
3. **Chase loop:** connected paths between bases and the commons, with enough bends and sightlines for short pursuits.

Home-to-home routes are approximately 120–180 studs. A carrier moves at 80% of normal walk speed, so a clean run takes about 9–14 seconds; the pickup and bank holds bring a full unchallenged theft to roughly 13–18 seconds.

## Mobile-first interface

The HUD contains Scrap, total Scrap per minute, occupied/max creature slots, one raid phase and timer, one next-goal card, and one contextual interaction prompt. It does not use a permanent inventory grid or multiple simulator-style panels.

All interaction buttons are at least 52 pixels across, use a single tap or a clearly labeled hold, and avoid precision aiming. A single prominent Tag button appears when a valid thief is close. Rarity uses a written label and icon as well as color. Audio moments have equivalent visual alerts; optional reduced particles and captioned sounds are supported.

## Visual and audio direction

The world is a bright oddities conservatory: clean shapes, saturated accent colors, readable silhouettes, and simple materials that remain legible on phone screens. Twelve base species share four body rig families. Each of the 24 mutation forms is a reusable visual recipe made from color/material, one shared accessory or silhouette detail, and a restrained effect. The project does not need 288 bespoke creature models.

Common forms add a clear tint or small detail; Uncommon forms add a distinct animated accent; Rare forms add a restrained aura and silhouette accent; Mythic forms use a standout palette, layered shared detail, and a unique but lightweight aura. Mutation visuals never change hitboxes, movement, or visibility rules.

Use short one-shot cues for capsule reveal, mutation start/reveal, Rare-or-better result, raid warning/start/end, theft in transit, Tag/drop, recovery, and escape. Income uses a grouped HUD tick at most once per 30 seconds, never a sound per creature or per payout. No large original soundtrack is required.

## Social play and retention

Players see each other's collections, can help Tag a carrier, and receive one server-wide announcement when a player equips a Mythic form. That announcement names the player and form but does not reveal a base location or income total.

A small Codex records 12 species and 24 mutation forms once discovered. It is a collection goal, not a power system. There are no login streaks, limited-time power items, clans, guilds, or trading.

See [PLAYER_FLOW.md](PLAYER_FLOW.md) for the 10-minute onboarding and 2-, 5-, 10-, 20-minute, and next-day retention goals.

## Included in V1

- Assigned base, two starting slots, one permanently protected starter, temporary theft protection for the specific Welcome Capsule creature until the first Raid in which the player participates completes, and one free guided Common mutation.
- One guaranteed-Uncommon Welcome Capsule, then repeatable Scrap capsules with visible odds and pity.
- Twelve species, three catalyst themes, 24 mutation forms, one active mutation per creature.
- Automatic online income and two permanent capacity upgrades.
- One shared eight-minute raid cycle, 15-second symmetric arrival grace for players who join during RAID, one attempted theft per creature per raid, one successful theft per thief per raid, and at most one loss per owner per raid.
- One mobile-friendly Tag action, recovery window for dropped creatures, and deterministic return on interrupted transfers.
- One compact map, the three map zones above, a small UI, and a 36-entry Codex.
- One optional cosmetic Game Pass planned for launch; product setup and implementation are outside this planning phase.

## Excluded from V1

Trading, clans, guilds, bosses, quests, multiple worlds, rebirths, complex crafting, combat weapons, skill trees, battle passes, following pets, large inventories, offline income, multiple currencies, extra raid types, base-defense upgrades, paid slots, paid luck, paid speed, paid recovery, paid random rewards, and large-scale content drops.

## Design freeze

The V1 design is frozen after the final design corrections. Do not add systems or expand scope unless later playtest evidence demonstrates a specific need and a new design decision approves the change.

## Design review and decision

| Review lens | Score | Reason |
| --- | ---: | --- |
| Player fun | 7/10 | Mutation reveals and short player-versus-player chases give the loop two distinct peaks; permanent theft still needs live testing. |
| Retention | 7/10 | The first session has an early collection goal and two visible raid cycles; repeat-session value depends on Codex completion and social play. |
| Build feasibility | 8/10 | Twelve species, 24 reusable mutation recipes, one map, one defense action, and a single raid state machine fit a small team. |
| Viral-moment potential | 7/10 | A Mythic reveal or a last-second Tag can be clipped, but sharing is an outcome to measure, not a guaranteed result. |

**Verdict: BUILD the MVP to a playtest, then validate the theft and onboarding gates before release.** The design is compact enough to prototype. This verdict is not a claim that retention, revenue, or virality has been proven.
