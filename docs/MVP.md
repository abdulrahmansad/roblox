# MVP scope and build milestones

## Locked V1 content

V1 includes 12 base creature species, 24 mutation forms in 3 catalyst themes, 1 currency, 2 starting creature slots with 2 permanent slot upgrades to a maximum of 4, 1 approximately 180 by 180 stud map with 3 functional zones, 1 shared raid type, 1 Tag defense action, a 36-entry Codex, and 1 cosmetic Game Pass planned for launch.

There are 8 players per server. The project targets one compact map and four reusable body-rig families. The only new-player protection is the permanently protected starting Mossling. Full details are in [GAME_DESIGN.md](GAME_DESIGN.md), [CREATURES.md](CREATURES.md), [MUTATIONS.md](MUTATIONS.md), [RAIDS.md](RAIDS.md), and [ECONOMY.md](ECONOMY.md).

## Excluded from the MVP

Trading, clans, guilds, quests, bosses, rebirths, weapons, skill trees, crafting, multiple worlds, extra raid types, offline income, base defense upgrades, extra currencies, large inventories, following pets, paid power, paid speed, paid luck, paid recovery, paid randomized rewards, and battle passes.

Post-launch candidates are limited to additional cosmetic palettes, creature skins that preserve rarity readability, and new mutation recipes using the same rigs. Each requires evidence from playtests before scope is expanded.

## Milestone plan

These are future implementation slices. This design-only task does not begin them. Each milestone should leave a playable/testable result and must meet its acceptance criteria before the next slice grows the scope.

| Milestone | Goal and included work | Excluded work | Player-visible result | Acceptance criteria |
| --- | --- | --- | --- | --- |
| M0 — Studio/Rojo smoke | Confirm Studio, Rojo sync, server/client startup, and two-client test path. | All gameplay systems. | A clean smoke experience starts in Studio. | Studio connects to Rojo; server and two clients start; documented smoke request succeeds and invalid request is rejected. |
| M1 — Session and base | Assign one of 8 base positions, show the shared phase clock, and handle joins/leaves. | Creature economy, raids, cosmetics. | Player spawns at an assigned base. | No duplicate assignments; leaving frees the base; a join inherits the server phase. |
| M2 — Starter and income | Persist 50 Scrap, Mossling, two slots; apply online 10-second income. | Capsules, mutation rolls, raids. | Mossling visibly earns Scrap. | Server calculates exact 40 Scrap/min base rate, tutorial Common changes it to 50, no offline income, payout carries fractions. |
| M3 — Capsules and capacity | Welcome/standard capsules, all 12 species, duplicates, sale, slot upgrades, capsule pity. | Mutations, Robux products. | Player can grow to four displayed creatures. | Odds and pity match docs; no client-selected result; costs, capacity, and sale floor hold under duplicate/replay requests. |
| M4 — Mutations | Three catalysts, 24 forms, tutorial guarantee, normal odds, pity, replace/keep interaction. | Mythic monetization, extra mutation systems. | Player can reveal and apply a form. | Server controls result, cost and pity; one active form; old form stays until accepted; tutorial is excluded from pity. |
| M5 — Raid state | Shared Peace/Warning/Raid/Resolution/Cooldown cycle and phase UI. | Theft and Tag. | Players can prepare for one timed raid. | Durations and transition order match the 8-minute cycle; joins inherit phase; server timer is authoritative. |
| M6 — Theft and Tag | Target locks, carry, bank, Tag, recovery, owner/thief disconnect and phase-end handling. | Weapons, extra defenses, multi-item carry. | Players can attempt theft and help stop a carrier. | At most one loss per owner, two attempts and one successful bank per thief, no starter theft, no duplicate transfer, all listed edge cases resolve once. |
| M7 — Persistence | Versioned player state, pity, creatures, slots, Scrap, Codex, idempotent raid journal. | Offline income, cross-server trading. | Progress survives leaving and rejoining. | Failed or duplicate saves do not duplicate or delete creatures; unbanked reservations reconcile to the owner. |
| M8 — Onboarding and mobile UI | 20-second tutorial, goal card, touch prompts, readable rarity, accessible alerts. | Large inventory and multiple HUD panels. | A first-time phone player can mutate, buy, and understand the next goal. | Touch targets meet 52-pixel minimum; first mutation is immediate; all required actions have touch input and clear feedback. |
| M9 — MVP content and audio | Complete 12 species, 24 reusable form recipes, three map zones, Codex, and cue set. | New worlds, bespoke 288-model combinations, full soundtrack. | A complete collection and readable world ship in one map. | Every species/form is identifiable; no mutation changes hitbox; all listed audio events have visual alternatives. |
| M10 — Balance and abuse playtest | Test economy, theft frustration, mobile chase, exploits, and 6–8-player behavior. | New features during balance pass. | The full free loop is stable in a live test. | No exploitable client authority; first capsule and first raid timings are measured; loss, recovery, and session exit data meet agreed gates. |
| M11 — Cosmetic monetization | Add one 99 Robux Curator's Palette Game Pass after gameplay gates pass. | Developer Products, paid power, random Robux rewards. | Buyer receives permanent palette/display cosmetics only. | Server verifies entitlement; repeated checks are safe; no stat, capacity, visibility, or raid advantage changes. |
| M12 — Release readiness | Final mobile/device, persistence, moderation, privacy, performance, and launch checks. | Unreviewed post-launch features. | Public MVP is ready for release. | Release checklist passes; rollback path and support ownership are documented; Creator Rewards is treated as uncertain and eligibility is checked in Creator Hub. |

## Playtest gates before release

The BUILD verdict means build a small playable test and collect evidence, not release without validation. Do not proceed to public launch until:

1. Most first-time testers can perform the guided mutation and state the goal without extra explanation.
2. A meaningful number reach the first Welcome Capsule within 2 minutes and understand the first raid before Warning ends.
3. Mobile players can Tag a carrier without aiming and can complete an unchallenged bank on representative phone hardware.
4. Losing one creature does not routinely cause immediate session exit; investigate losses by rarity and time owned.
5. 6–8-player tests show no duplicate theft, stale ownership, phase race, or persistence loss.

## Risk register

Likelihood and impact are scored 1–5; priority is their product.

| Rank | Risk | Likelihood | Impact | Priority | Mitigation and evidence needed |
| --- | --- | ---: | ---: | ---: | --- |
| 1 | Permanent theft makes players quit after losing a valuable mutation. | 4 | 5 | 20 | Starter floor, one loss per victim per raid, no Scrap loss, one 8-minute cycle; measure exits by loss value and time-to-quit. |
| 2 | Touch chase or Tag feels inconsistent on mobile latency. | 4 | 4 | 16 | 7-stud server range, no aiming, one Tag, 5-second immunity, clear prompts; run phone tests across network conditions. |
| 3 | Shared raid phase means some joins see a raid immediately or wait for the next phase. | 3 | 4 | 12 | Immediate phase/status UI, starter protection, first-session test across join phases; avoid personal raid resets that create unfair timing. |
| 4 | Mutation pity and income rates make choices too slow or Mythics too common. | 3 | 4 | 12 | Visible odds/pity, no paid odds, bounded multipliers; measure roll count, mutation spend, income growth, and form rarity. |
| 5 | Small art team cannot make 12 species and 24 forms readable at phone size. | 3 | 3 | 9 | Four rig families and shared recipes; test silhouette and rarity recognition before producing all variants. |

## Small-team and player review

The MVP has one map, three functional zones, 12 species, 24 shared form recipes, two capacity upgrades, one raid state machine, one defense action, and one launch cosmetic product. It avoids clans, trading, quests, combat, multiple worlds, and a second currency.

For a young player, the immediate reward is a free mutation and the next action is one capsule purchase. For a phone player, every core action uses a large contextual control. A 3-minute player sees both mutation and acquisition. A 10-minute player reaches the first raid. Friends can help without a clan feature. A player who loses still keeps the starter and earned currency, though the risk of quitting remains the top experiment.

## Anti-frustration review

| Concern | Design response | Remaining playtest question |
| --- | --- | --- |
| Is theft too punishing? | Only one creature can be lost per owner per 8-minute cycle; Scrap and the starter are never lost. The owner or another player can Tag the carrier before the bank. | How often does losing a Rare or mutated creature cause an immediate exit? |
| Can stronger players bully weaker players? | There are no level-based multipliers. Each owner has one loss limit and one active base lock; each thief has two attempts and one successful bank maximum. | Do coordinated groups still focus one target despite the limit? |
| Will AFK players lose everything? | Offline bases cannot be targeted. An online idle owner can lose at most one non-starter, while the starter and all Scrap remain. No extra idle shield is stacked on top. | Is one loss acceptable to an online player who is not actively watching? |
| Can someone lose hours of progress in 30 seconds? | No currency is stolen and only one creature transfers; the full pickup-and-bank run takes about 13–18 seconds without interception. The owner has a Tag and recovery opportunity during the transfer. | Rare creature loss can still represent substantial time and is a release gate. |
| Can friends abuse teaming? | Tagging can help a friend, but no trading or Scrap transfer exists. Theft does not award Scrap, and each participant can earn only one catalyst per raid. Ownership moves once; it never duplicates. | Test repeated friend-to-friend transfers and reward farming in multi-raid sessions. |
| Is a rare creature too easy to steal? | Rare creatures are stealable, but there is one loss per owner, a base lock, a server-validated carry, and Tag/interception before bank. | Measure bank success by creature rarity and whether nearby defenders had a fair chance to react. |
| Is mutation too random? | The first outcome is guaranteed Common, normal odds are visible, pity is bounded, and the previous mutation remains until the player accepts a replacement. | Check whether 160 Scrap plus a catalyst feels fair after the first session. |
| Is progression too slow or too fast? | The model puts the Welcome Capsule near 1:30, a real spend choice near 3:00, Slot 3 near 5:00 if saved for, and Slot 4 around 12:34 on the modeled path. | Replace modeled averages with observed data before launch; rare rolls and raid results will widen the range. |

The design accepts that a successfully banked creature is permanently transferred. The counterweights reduce the number and timing of losses; they do not remove the emotional risk. If playtests show that loss-driven exits remain high, revise theft persistence before adding more content or monetization.
