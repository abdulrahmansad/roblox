# Roblox game foundation

This repository is the source of truth for Oddlings: Mutation Run, a small multiplayer creature mutation game. The V1 design is frozen. M1 session/base services, M2 profiles/online Scrap income, and the portable M3 capsule/creature/sale/capacity implementation are in place. M4 mutation implementation is starting; M5–M12 remain. M0/M1/M2/M3 Studio checks are pending.

## Prerequisites

- Windows 10/11 (scripts use PowerShell 7-compatible syntax and also work in Windows PowerShell 5.1).
- Git.
- Roblox Studio, signed in to a Roblox account, for interactive and multiplayer playtests.
- Rokit 1.2.0 or newer. The project pins Rojo, Wally, StyLua, Selene, and Lune in `rokit.toml`.

Install Rokit using its [official Windows instructions](https://github.com/rojo-rbx/rokit#installation), then open a new terminal so its user PATH entry is loaded. Run the project setup:

```powershell
./scripts/setup.ps1
```

This installs the pinned CLI tools and Wally packages. Setup does not install Roblox Studio or sign in to Roblox.

## Daily workflow

```powershell
./scripts/serve.ps1       # Start Rojo live sync, then connect with the Rojo Studio plugin
./scripts/format.ps1      # Format Luau files
./scripts/lint.ps1        # Run Selene
./scripts/test.ps1        # Run portable Lune tests
./scripts/build.ps1       # Build a place file under build/
./scripts/verify.ps1      # Format check, lint, tests, and Rojo build
```

In Studio, open a baseplate or place, install the official Rojo 7 plugin from the [Rojo installation guide](https://rojo.space/docs/v7/getting-started/installation/), then click **Connect** and use `localhost:34872`. For live server/client behavior, use **Test**. For multiplayer, select **Server & Clients**, choose up to eight clients, and start the session. See [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes).

## Repository layout

- `src/shared`: shared protocol, configuration, types, and utilities.
- `src/server`: server bootstrap, services, security, and future persistence boundaries.
- `src/client`: client bootstrap and presentation-only code.
- `tests`: portable unit/integration/security tests and Studio multiplayer test plans.
- `docs`: locked game design, creature roster, mutations, raids, economy, monetization, player flow, architecture, profile schema, network protocol, state machines, M0–M12 milestones, security, analytics, tooling, testing, and status. [BUILD_START_CHECKLIST.md](BUILD_START_CHECKLIST.md) records readiness gates.
- `DevPackages`: Wally-generated development packages; ignored by Git and mapped to `ServerStorage`.
- `build`: generated place files; ignored by Git.

## Troubleshooting

- `rokit` not found: reopen PowerShell after installing Rokit or add `%USERPROFILE%\.rokit\bin` to your user PATH.
- Pinned tools missing: run `rokit install` from the repository root.
- Wally packages missing: run `wally install` or `./scripts/setup.ps1`.
- Rojo Studio plugin cannot connect: ensure `rojo serve` is running and the plugin is Rojo 7; use `localhost:34872`.
- `verify.ps1` fails: fix the first reported command failure, then rerun the full verification command.
- Studio is not installed: local formatting, lint, portable tests, and place builds still work; Studio-only multiplayer execution remains unavailable until Studio is installed and signed in.

Read [AGENTS.md](AGENTS.md) and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) before making project changes.

The locked V1 design starts at [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md). Follow [docs/MILESTONES.md](docs/MILESTONES.md) for implementation scope and acceptance; do not expand the frozen design.
