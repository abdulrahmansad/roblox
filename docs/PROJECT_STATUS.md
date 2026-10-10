# Project status

Status: development foundation initialized. The final V1 design corrections are applied and the game design is frozen. Gameplay implementation remains unstarted and is outside the scope of the design-only phase.

## Design

- Approved concept and V1 scope are in [GAME_DESIGN.md](GAME_DESIGN.md).
- Creature roster, mutation outcomes, raid rules, economy, monetization, player flow, and build milestones have dedicated documents.
- The design verdict is BUILD to a playtest, with permanent theft and mobile chase fairness as the first validation risks.

## Development foundation

- Repository rules, Rojo source mapping, pinned CLI manifest, setup/verification scripts, foundation documentation, and seven project-local Roblox skills are present.
- The technical smoke path covers a server-validated request with a portable Lune suite and a Roblox TestEZ spec.
- The last recorded foundation verification passed formatting, lint, four portable tests, and the Rojo build. It was not rerun for this documentation-only design update.
- Roblox Studio was not detected during the prior foundation inspection. M0 Studio/Rojo smoke validation remains pending: install Studio from Roblox Creator Hub, sign in, install the Rojo Studio plugin, then complete the documented two-client smoke path.

## Repository state

- Current branch is main.
- The configured origin currently has no reachable remote tracking ref.
- This design update changes planning documents and agent guidance only; it adds no gameplay code or runtime systems.
