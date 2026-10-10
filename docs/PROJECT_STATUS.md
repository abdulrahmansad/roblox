# Project status

Status: pre-build readiness documentation is complete. V1 design is frozen. No gameplay/runtime system was implemented in this phase. The remaining build gate is the human-only Roblox Studio/Rojo M0 smoke listed in [BUILD_START_CHECKLIST.md](../BUILD_START_CHECKLIST.md).

## Locked planning contracts

- Approved V1 scope and player-facing design: [GAME_DESIGN.md](GAME_DESIGN.md), with the final Welcome protection boundary in [RAIDS.md](RAIDS.md).
- Planned module ownership and dependencies: [ARCHITECTURE.md](ARCHITECTURE.md).
- Exact profile fields, defaults, migration and corruption rules: [DATA_MODEL.md](DATA_MODEL.md).
- Planned request/result/event shapes and server validation: [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md).
- Raid, theft, mutation and Welcome participation transitions: [STATE_MACHINES.md](STATE_MACHINES.md).
- Future behavior and Studio test coverage: [TESTING.md](TESTING.md).
- M0–M12 scope, dependencies, acceptance, documentation and commit boundaries: [MILESTONES.md](MILESTONES.md).

## Tooling and verification

The pinned tools match `rokit.toml`: Rokit 1.2.0, Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, and Lune 0.10.5. Wally TestEZ 0.4.1 is installed in the ignored development package directory.

The canonical `./scripts/verify.ps1` passed formatting, lint (0 errors/warnings/parse errors), all four portable tests, and the Rojo build. The bundled skill validator passed all seven `.agents/skills` folders. Local Markdown links were checked. `./scripts/serve.ps1` started Rojo on `localhost:34872`; the local HTTP endpoint returned 200. `default.project.json` built successfully. The serve process was stopped after the check.

## Studio status

Roblox Studio was not detected in PATH, installed Appx packages, or the local Roblox Studio installation/plugin locations inspected for this task. Studio login and Rojo plugin connection therefore could not be verified. The documented two-client M0 smoke remains pending; no Studio success is claimed. Install Studio, sign in, install the Rojo 7 plugin, connect to the local Rojo server, and complete [the two-client smoke](../tests/multiplayer/README.md).

## Git status

The readiness changes are committed on `main` and pushed to the configured `origin` at `https://github.com/abdulrahmansad/roblox.git`. Remote `main` matches local HEAD and the worktree is clean. No force push was used.
