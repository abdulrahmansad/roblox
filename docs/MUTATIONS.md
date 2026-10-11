# Mutation system

## Materials and cost

There are three catalyst items, each bound to its matching mutation theme:

| Catalyst | Theme |
| --- | --- |
| Ember Seed | Ember |
| Prism Dust | Prism |
| Moss Spore | Moss |

A player chooses one catalyst at the start. The first guided mutation consumes it, costs no Scrap, and is guaranteed to produce one of that theme's four Common forms. Each Common has an equal 25% chance in the tutorial. This tutorial result does not affect pity.

After the tutorial, a normal mutation costs 100 Scrap and one catalyst. A matching catalyst can be bought at the commons kiosk for 60 Scrap or earned as one chosen catalyst after a successful theft deposit. A player can earn at most one catalyst per raid from successful theft deposits. Tags never award catalysts, even when they successfully stop a theft. Catalysts are items, not currencies.

The guaranteed Common tutorial is available immediately and takes about 20 seconds of optional guided interaction. It has no forced animation delay.

## Forms, tiers, and roll odds

Each branch has eight named forms: four Common, two Uncommon, one Rare, and one Mythic. Normal roll odds are the same in all three branches.

| Result tier | Total chance | Chance per named form | Income multiplier |
| --- | ---: | ---: | ---: |
| Common | 60% | 15% each of 4 | ×1.25 |
| Uncommon | 30% | 15% each of 2 | ×1.5 |
| Rare | 9.9% | 9.9% | ×2 |
| Mythic | 0.1% | 0.1% | ×4 |

### Ember

| Tier | Form | Shared visual cue |
| --- | --- | --- |
| Common | Cinder | Charcoal color with small orange fissures |
| Common | Sparkcap | Bright cap tint with one brief spark accent |
| Common | Coalcoat | Matte dark mantle with ember-colored seams |
| Common | Toastbite | Warm toasted patches and a simple bite-mark decal |
| Uncommon | Flarefin | Shared flame-shaped back fin |
| Uncommon | Hearthhorn | Paired ember horns |
| Rare | Sunheart | Gold chest core and small ring accent |
| Mythic | Starforge | Dark forge-metal plates and a lightweight orbiting star |

### Prism

| Tier | Form | Shared visual cue |
| --- | --- | --- |
| Common | Glint | High-contrast pinprick highlights |
| Common | Opalcoat | Iridescent surface tint |
| Common | Shardtail | Shared small crystal tail fin |
| Common | Splitlight | Two-tone split palette |
| Uncommon | Aurora | Translucent ribbon with a slow color sweep |
| Uncommon | Mirrorflash | Reflective face plate and one short glint |
| Rare | Spectrum | Segmented rainbow edge light |
| Mythic | Paragon | Faceted crown and restrained prismatic halo |

### Moss

| Tier | Form | Shared visual cue |
| --- | --- | --- |
| Common | Sprout | Two small leaf sprouts |
| Common | Puffcap | Rounded mushroom cap |
| Common | Lichen | Textured green patches |
| Common | Vinewrap | One vine band around the body |
| Uncommon | Bloomguard | Single flower-shaped shoulder shield |
| Uncommon | Boglight | Soft cyan spots and a low glow |
| Rare | Worldroot | Broad root cuffs and branching accents |
| Mythic | Verdant Crown | Leaf crown and a lightweight root halo |

## Applying and replacing a mutation

Each creature can have one active mutation. A new roll never removes the active form automatically. Once a paid roll is revealed, the player can keep the current form or replace it with the new result. Declining a result does not refund Scrap or its catalyst. The new result is only added to the Codex when equipped.

A result matching the creature's active form is a duplicate: it cannot stack or create a second copy on that creature. The cost and pity roll still count, and the player keeps the active form. A player can roll the same form on another creature separately.

A player can have only one mutation transaction in progress. A second request while that transaction is pending is rejected without charge. A mutation multiplies the creature's base Scrap/min by the listed tier multiplier; multipliers never stack. A mutation can be rolled only while its creature is in its stand and not reserved for a raid transfer. Mutations are unavailable during RAID and RESOLUTION. The result reveal takes about 2 seconds and can be skipped.

## Pity and fairness

Normal mutation rolls have one persistent, server-owned Rare-or-better pity counter shared across all three themes:

- After 8 normal rolls without a Rare-or-better result, the next roll is at least Rare.

A Rare or Mythic resets the Rare-or-better counter; any result below Rare increments it. A Mythic has a 0.1% base chance on every normal mutation roll, including when Rare-or-better pity is active. When the Rare-or-better guarantee is active, the next-roll odds are 99.9% Rare and 0.1% Mythic; otherwise the normal odds in the table apply. The guarantee never adds a Mythic chance or changes the 0.1% Mythic chance. There is no Mythic pity, Mythic miss counter, or other mechanic that increases Mythic odds. The free tutorial roll is excluded. Before confirmation, the station shows the normal odds, current Rare-or-better pity state, and exact odds for the next roll. No Robux purchase changes odds or pity.

## Visual and audio treatment

Every form uses a shared recipe across all 12 creatures: palette/material, one shared accessory or silhouette detail, and a lightweight effect. Common is clearly recolored with its form detail; Uncommon adds a gently bobbing detail; Rare adds a restrained occluded highlight; Mythic adds its layered palette, form detail, and stronger restrained highlight. The FX control lowers sound volume and disables motion/highlights. Effects do not change hitboxes, movement, or raid visibility. Studio review is still needed to confirm materials and effects read well on device screens.

The player sees a theme-colored catalyst, normal odds, current Rare-or-better pity state, any active next-roll guarantee and its exact odds, Scrap cost, and the exact creature affected before confirming. The reveal combines a short machine cue, a tier label, and a brief silhouette-to-form transition. A Mythic announcement goes to the server only after the player equips the Mythic, and it does not expose the player's base location.
