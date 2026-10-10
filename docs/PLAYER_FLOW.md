# First session, retention, and mobile UX

## First 10 minutes

The timestamps below describe a new player entering a fresh server. A player joining an existing server inherits its current shared raid phase; they do not get a private cycle.

| Time | Player experience |
| --- | --- |
| 0:00 | Spawn directly at an assigned 22 by 18 stud base. The player sees 50 Scrap, a Mossling producing 40 Scrap/min, two slots, and the Welcome Capsule price. |
| 0:00–0:20 | One sentence explains the loop: “Mutate your oddling, add more, and when the siren hits, steal one and bring it home.” The player chooses Ember, Prism, or Moss. |
| By 0:30 | A short, skippable guided interaction consumes the free chosen catalyst and applies a guaranteed Common mutation to the Mossling. It now earns 50 Scrap/min. No forced wait or wall of text. |
| 0:30–1:30 | A single goal card says to visit the capsule kiosk. The player can walk through the commons, inspect visible neighboring creatures, and see Scrap accumulate automatically. |
| About 1:30 | 120 Scrap is available. The Welcome Capsule guarantees one Uncommon species. The reveal displays its name, income, and rarity; the player places it in the second stand. |
| 1:30–3:00 | The player sees the two-creature income rate and an optional mutation station prompt. At about minute 3, the player has roughly 194 Scrap and chooses between a 160 Scrap mutation roll and saving toward the 350 Scrap third slot. |
| 3:00–5:00 | The goal card changes to the chosen next step. Neighbor bases remain inspectable; no manual collection chore is added. |
| 5:00–5:30 | First Warning. Gates open, siren and countdown begin, and the player can see nearby targets and return routes. |
| 5:30–7:00 | First Raid. The player can attempt one theft, defend with Tag, or help interrupt a carrier. Theft remains optional; income continues. |
| 7:00–8:00 | Resolution returns unfinished transfers, then a short result summary plays during Cooldown. |
| 8:00–10:00 | Peace resumes. The player chooses another creature, mutation, or slot. At minute 10 in a fresh-server timeline, the next Warning is three minutes away, so the first session ends with a clear next goal. |

The 3:00 balance estimate assumes the Welcome Capsule's expected Uncommon income: 5 Scrap remaining at 1:30 plus 1.5 minutes at 126 Scrap/min is about 194 Scrap. Species variation changes the exact amount.

## Retention moments

| Session point | Why stay |
| --- | --- |
| 2 minutes | The player has already mutated a creature and revealed an Uncommon capsule. |
| 5 minutes | The player has a real choice between improving a creature and expanding capacity, plus a visible raid countdown. |
| 10 minutes | The first raid has produced a story or a near miss; the next raid is approaching and Slot 3/next mutation is reachable. |
| 20 minutes | The second raid has resolved; there is room to show a new creature or mutation and set a next collection goal. In a fresh timeline, the third Warning starts at minute 21. |
| Tomorrow | A persistent 36-entry Codex shows missing species and mutation forms. There is no streak, expiring reward, or penalty for not returning. |

## Minimum HUD and touch actions

- Top status: Scrap, total Scrap/min, occupied/max slots, current raid phase and countdown.
- One goal card: next useful action, such as “Welcome Capsule: 120 Scrap” or “Slot 3: 350 Scrap.”
- One contextual prompt: interact, Steal, or Tag, depending on phase and distance.
- Mutation and capsule panels show price, result odds, selected creature, and confirmation in one compact view.
- No persistent inventory grid, scrolling shop, or manual collect button.
- Primary controls are at least 52 pixels across. Hold duration is shown as a radial fill. Any hold can be canceled by moving away.
- Tag is one large context button on mobile, and one keyboard action on desktop. It does not require aiming.
- Rarity is conveyed with text, icon, and color. Captions/visual alerts cover important sound cues; reduced effects are supported.

## Sound and feedback schedule

Use brief cues for capsule acquired, machine start, mutation reveal, Rare-or-better, Warning, Raid start, creature in transit, banked theft, successful Tag/drop, owner recovery, thief escape, and Raid end. A grouped income cue happens at most once every 30 seconds per player. No repeated per-creature coin sounds or full soundtrack production are needed.

## Player review

- **Age 10–14:** One sentence and one guided action explain the loop; rarity uses names/icons, not color alone.
- **Phone player:** No precision clicking, inventory dragging, or aim-based defense. The chase uses contextual holds and a large Tag control.
- **Three-minute player:** Has a mutation, a capsule, and a mutation-versus-slot decision.
- **Ten-minute player:** Has completed one raid and can choose a concrete next goal.
- **Player who lost a creature:** Keeps the protected Mossling, all earned Scrap, and all other creatures. One loss maximum per owner per raid; no currency loss. The loss can still feel bad and is the primary playtest risk.
- **Player who got a rare form:** Keeps the form on a visible stand, sees an exact rarity label, and gets a Mythic server announcement when equipped.
- **Friends:** Can join the same server through Roblox, inspect bases, and help Tag a carrier. No special alliance or clan system is needed.
