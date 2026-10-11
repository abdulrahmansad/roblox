# Creatures and acquisition

## Species and base income

Income is measured in Scrap per minute before mutation. Each base species has one fixed rate.

| Base rarity | Species | Silhouette read | Scrap/min |
| --- | --- | --- | ---: |
| Common | Mossling | Round seed body with two leaf nubs | 40 |
| Common | Tiffin Toad | Squat frog shape with a kettle-like back | 36 |
| Common | Puddle Pup | Pear-shaped body with floppy drop ears | 38 |
| Common | Button Bat | Wide little wings and oversized button eyes | 42 |
| Common | Noodle Finch | Tall narrow body and long ribbon tail | 44 |
| Common | Pebble Imp | Chunky asymmetrical stone back and tiny horns | 46 |
| Uncommon | Teacup Crab | Low crab legs under a cup-shaped shell | 70 |
| Uncommon | Static Finch | Sharp feather crest and zigzag tail plume | 74 |
| Uncommon | Velvet Gremlin | Soft egg-shaped body and oversized ears | 78 |
| Uncommon | Clockwork Carp | Oval fish body with squared clocklike fins | 82 |
| Rare | Lantern Yak | Broad body, sweeping horns, lantern chest | 110 |
| Rare | Pocket Hydra | Compact body with three small neck heads | 120 |

The only starting species is Mossling. The starting Mossling instance is permanently protected from theft and sale. A Mossling acquired later is an ordinary creature. The specific creature awarded by the Welcome Capsule is also protected from theft until the first Raid in which the player participates completes, as defined in [RAIDS.md](RAIDS.md); disconnecting after participation does not extend protection, and a late join whose grace lasts through the RAID phase does not consume it. This temporary rule does not protect Scrap or any other creature.

## Acquisition and capsule odds

Every player starts with 50 Scrap and one assigned base. The first capsule is the **Welcome Capsule**, costs 120 Scrap, and guarantees one of the four Uncommon species uniformly at 25% each. At the default starting income, the first purchase is available at about 1:30.

Further capsules cost 120 Scrap and use these tier odds:

| Tier | Chance | Species selection |
| --- | ---: | --- |
| Common | 70% | Uniform among 6 species |
| Uncommon | 25% | Uniform among 4 species |
| Rare | 5% | Uniform among 2 species |

The standard capsule has persistent, server-owned pity across sessions: after 3 consecutive standard outcomes below Uncommon, the next standard capsule is at least Uncommon; after 8 consecutive standard outcomes below Rare, the next is Rare. A Rare satisfies both floors. The Welcome Capsule does not advance or reset pity. Odds and the visible pity state are shown before purchase. Duplicates are allowed.

All capsule rolls happen on the server. A client can request a capsule purchase but cannot select its result or supply a rarity.

## Base capacity and display

Players begin with 2 slots and may permanently buy:

| Upgrade | Cost | Unlock condition | Result |
| --- | ---: | --- | --- |
| Slot 3 | 350 Scrap | Own 2 creatures | Capacity becomes 3 |
| Slot 4 | 1,200 Scrap | Player's first participated Raid has completed and they own 3 creatures | Capacity becomes 4 |

There are no other base upgrades in V1. Slots are not purchasable with Robux.

Each creature occupies one visible stand. A player can inspect another base from outside and see species, base rarity, mutation name/rarity, and exact current Scrap per minute. Base rarity and mutation rarity are labeled separately. Duplicate species have the same income and appearance recipe.

## Income and selling

Income accrues automatically every 10 seconds while the player is in a live server, across all raid phases. The server aggregates per-creature income, carries fractional Scrap between payouts, and credits whole Scrap without rounding loss. There is no offline income and no collect button.

A player may sell any non-starter creature at the commons kiosk for 60 Scrap. This is a 50% loss against a 120 Scrap capsule and does not make acquisition profitable. A confirmation shows the creature, its mutation, current income, and refund before the sale completes. The starting Mossling cannot be sold. Creatures currently targeted, reserved, carried, or being mutated cannot be sold. There is no trading or player-to-player transfer outside the raid system.

## Collection scope and production

The Codex has 12 species entries and 24 mutation-form entries. Discovering a form on any species fills that form entry; it does not require collecting all 288 species/form pairings. Creature instances are displayed in place rather than carried in a large inventory.

The art target is 12 readable species silhouettes assembled from four shared body-rig families, plus 24 shared mutation recipes. Rarity does not alter collision size or movement.

## V1 presentation

`CreatureVisualDefinitions` contains one reusable silhouette/palette for each species and one palette/material/detail/effect recipe for each mutation form. The client builds these as anchored local display models over the server's stand markers; client models have no collision, touch, or query behavior. The server markers continue to carry the authoritative creature ID, species, and active form. Inspection labels show species and base rarity, mutation and mutation rarity, and current Scrap/min. The map blockout keeps eight pads within the 180 by 180 stud ground, with a Commons circle, an octagonal chase route, four Commons spokes, and eight base approaches. The client Codex lists each of the 12 species and 24 forms once, hiding undiscovered names behind generic labels.

Studio inspection is still required to judge silhouettes, material readability, billboard overlap, low-end performance, and audio asset loading in the running experience.
