# Monetization design

## Principles and status

This document plans monetization only. No product IDs, shop UI, receipt handler, or Robux purchase has been created. The complete free gameplay loop includes every creature, mutation, slot, raid, and progression goal.

Roblox's current engagement program is called Creator Rewards; the older Engagement-Based Payouts program was deprecated and replaced. Program terms and eligibility can change, so check the [Creator Rewards documentation](https://create.roblox.com/docs/creator-rewards) before release. Do not forecast Creator Rewards as guaranteed income or add fake waiting, alternate-account activity, or coercive streaks to chase it. Build genuine session value through the collection, mutation reveals, and player-created chase moments.

The only launch product planned is a one-time permanent cosmetic Game Pass. Roblox documents passes as one-time Robux purchases for permanent benefits; see [Passes](https://create.roblox.com/docs/production/monetization/passes).

## MVP launch product

| Product | Proposed price | Grant | Duration | Gameplay and raid impact |
| --- | ---: | --- | --- | --- |
| Curator's Palette Game Pass | 99 Robux initial listed price | Three alternate base palettes and one matching display-pedestal trim | Permanent | Cosmetic only. It changes no stats, creature visibility, hitboxes, capacity, income, odds, or raid rules. |

The normal palette remains the default. A player who never buys the pass can acquire every gameplay item and reach the same four-slot cap. The pass is not prompted during a raid, after a loss, or in response to a failed mutation. Its price is a launch hypothesis and can be adjusted before publication after storefront review; no pass or price is configured during this design phase.

## Purchase ideas reviewed

| Idea | What the player would receive | Duration | Pay-to-win risk | Free progression equivalent | Frustration and raid effect | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| Extra creature slot | One more income/display slot | Permanent | High: more income and more collection capacity | No need for a paid slot; all players reach the V1 cap of 4 | Adds a capacity and income advantage that can affect targets and raid stakes | Reject |
| Cosmetic base theme | Palette and trim only | Permanent | None if it does not change visibility | All gameplay remains available free | Low; must not hide creatures or obscure rarity | MVP: Curator's Palette |
| Mutation luck boost | Higher chance of Rare/Mythic or faster pity | Temporary or permanent | Severe: sells income and status advantage | Free players could not reach the same odds | Makes disclosed odds and earned Mythics less trustworthy | Reject |
| Temporary speed/convenience boost | Faster running, pickup, or cooldowns | Temporary | High during a chase | No equivalent that preserves raid fairness | Directly changes theft and Tag outcomes | Reject |
| Creature skin | A visual species variant | Permanent | Low only if it preserves silhouette and rarity readability | Could be cosmetic-only; all income and mutation progression stays free | Risk of implying a higher rarity or hiding the target | Post-launch only, after phone readability testing |
| VIP visual effects | Nameplate, aura, or base effect | Permanent or temporary | Low to medium | No gameplay equivalence is needed | Can clutter the chase or make mutation rarity harder to read | Defer; only reconsider as restrained cosmetics |
| Extra storage/slots | More collection capacity | Permanent | High: effectively an extra slot and income | Base game already has four slots | Changes collection and raid economics | Reject |
| Paid currency or capsules | Scrap, guaranteed species, or random creature | Consumable | High: accelerates income and slot progression | Free play can earn the same content, but paid acceleration pressures the balance | Paid random rewards weaken fairness and complicate odds disclosure | Reject for V1; no paid random rewards |
| Paid protection or recovery | Shield, return, or restoration after theft | Temporary or permanent | High: changes raid risk | A free version would need to be identical | Monetizes frustration at the moment of loss | Reject |
| Private-server raid bypass | Reduced/no raids in a private session | Session-based | Medium: bypasses the main social loop | Public servers remain free | Splits the experience and avoids its defining interaction | No MVP product |
| Developer Products | Repeatable consumables | Consumable | Depends on grant | Not needed for the MVP | More purchase and receipt complexity without a needed player benefit | Zero planned for launch |

The single cosmetic pass is the only Robux product counted in V1. Do not add monetization simply to fill a shop.

## Future implementation requirements

If the pass is approved after playtests, the server must verify its entitlement. The client may show the price and prompt a purchase but cannot grant the palette. Receipt or entitlement checks must be idempotent, recover from service errors, and never change a player's economy or raid state. The product catalog must remain separate from presentation and server fulfillment.
