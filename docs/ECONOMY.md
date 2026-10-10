# MVP economy

## Economy rules

- The only currency is Scrap. Ember Seed, Prism Dust, and Moss Spore are catalyst items, not currencies.
- New players start with 50 Scrap, one Mossling, two slots, and one chosen catalyst.
- Income is automatic in 10-second payouts while online, including during raids. There is no offline income, manual collection, or raid currency loss.
- Each creature's base income is defined in [CREATURES.md](CREATURES.md). Active mutation multipliers are defined in [MUTATIONS.md](MUTATIONS.md).
- All balances, payouts, purchases, sales, pity, and rewards are server-owned.

## Prices and rewards

| Item/action | Price or reward | Notes |
| --- | ---: | --- |
| Welcome Capsule | 120 Scrap | First capsule; guarantees an Uncommon species. |
| Standard Capsule | 120 Scrap | 70% Common, 25% Uncommon, 5% Rare, with capsule pity. |
| Normal mutation | 100 Scrap + 1 catalyst | Catalyst costs 60 Scrap if purchased. |
| Tutorial mutation | Free | One chosen catalyst is provided and consumed; guaranteed Common. |
| Catalyst kiosk | 60 Scrap each | Three branch-bound types. |
| Successful theft deposit | 1 chosen catalyst | Maximum one earned catalyst per thief per raid. |
| Sell non-starter creature | 60 Scrap | Fixed return; the starter cannot be sold. |
| Slot 3 | 350 Scrap | Requires two owned creatures. |
| Slot 4 | 1,200 Scrap | Requires first raid complete and three owned creatures. |

No action takes currency from a victim. A defensive Tag awards no catalyst; preventing the creature loss is its reward. Catalyst rewards do not stack with a purchase discount; each normal mutation still needs one matching catalyst.

## Progression model

The first guided Common mutation makes the starter Mossling earn 50 Scrap/min (40 × 1.25). The Welcome Capsule arrives at about 1:30 and has an expected 76 Scrap/min (uniform among the four Uncommon species). After that purchase the expected two-creature rate is 126 Scrap/min.

The first decision is deliberately a tradeoff. Around minute 3, a player can spend 160 Scrap for a catalyst plus a normal mutation roll, or save toward Slot 3 at 350 Scrap. A third creature costs another 120 Scrap. Slot 4 is a later capacity goal, not a required early purchase.

## Modeled snapshots

These are planning estimates, not guaranteed acquisition times. They use the average species income for random capsules, assume no theft (and therefore no theft-deposit catalyst reward) and no normal mutation spending. The tutorial mutation is included. Capsule pity, Rare-or-better mutation pity, and individual species rolls can move actual balances.

| Time | Modeled state | Expected unspent Scrap |
| --- | --- | ---: |
| 1:30 | Starting 50, Welcome Capsule bought for 120, two creatures, expected 126 Scrap/min | 5 |
| 5:00 | Two creatures; player can buy Slot 3 for 350 or save for a mutation/capsule | 446 before spending |
| 7:30 | Slot 3 bought at minute 5; second capsule bought when Cooldown begins; three creatures at expected 179.45 Scrap/min | 291 after the capsule |
| 10:00 | Three creatures, Slot 3, first raid resolved, second Peace underway | About 740 |
| 12:34 | With no further spending after minute 7:30, Slot 4 becomes affordable during Warning | 0 after the 1,200 purchase |
| 15:30 | Fourth slot is open; a third capsule can be bought when the second Raid's Cooldown begins | About 407 after that capsule |
| 30:00 | Four creatures and four slots; no further purchases after minute 15:30 | About 3,836 |

Calculation notes:

- Minute 5: 5 Scrap left after the Welcome Capsule plus 3.5 minutes at 126/min = 446.
- Minute 10: after Slot 3, 96 Scrap at minute 5; 2.5 minutes at 126/min yields 411; buy a 120 Scrap capsule when Cooldown begins at minute 7:30; then 2.5 minutes at the expected 179.45/min yields about 740.
- Minute 30: after Slot 4 is bought at about 12:34, save until Cooldown begins at minute 15:30, buy another 120 Scrap capsule, then earn at the expected four-creature rate of 232.9/min through minute 30.

The minute-30 balance is intentionally a spend-light model, not the ideal player behavior. A player who buys mutations or suffers a theft has less Scrap but may have higher income, a new catalyst, or a more interesting collection. A Common mutation on an Uncommon creature raises expected income from 76 to 95 Scrap/min, so the 160 Scrap all-in mutation cost is meaningful but reachable within the first session.

## Inflation and balance guardrails

- Standard capsule price stays at 120 while base income ranges from 36 to 120 Scrap/min. The 60 Scrap sale value is always below capsule cost.
- Slot costs rise from 350 to 1,200 and are one-time, permanent sinks.
- Mutation costs do not compound, and a creature can have only one active mutation.
- The Mythic multiplier is powerful but constrained by an exact 0.1% chance on every normal mutation roll. There is no Mythic pity or other odds boost; it cannot be bought directly or boosted with Robux.
- Recheck this model with real playtest telemetry before release. Track time to first capsule, first standard mutation, Slot 3, Slot 4, average Scrap/min, loss/recovery rates, and the share of players who spend versus save.
