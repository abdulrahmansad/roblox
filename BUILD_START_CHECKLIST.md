# Build start checklist

This checklist records the current pre-build state. Gameplay implementation has not started.

| Gate | Status | Evidence |
| --- | --- | --- |
| V1 design frozen | **PASS** | [GAME_DESIGN.md](docs/GAME_DESIGN.md) and approved V1 scope. |
| Final Welcome protection rule fixed | **PASS** | [RAIDS.md](docs/RAIDS.md), [DATA_MODEL.md](docs/DATA_MODEL.md): participation is durable; disconnect after participation cannot preserve protection; grace through RAID end does not consume it. |
| Architecture locked | **PASS** | [ARCHITECTURE.md](docs/ARCHITECTURE.md) defines modules, locations, authority, dependencies, interfaces, and tests. |
| Data model locked | **PASS** | [DATA_MODEL.md](docs/DATA_MODEL.md) defines schema v1, defaults, migrations, corruption policy, ownership, and runtime-only state. |
| Network protocol locked | **PASS** | [NETWORK_PROTOCOL.md](docs/NETWORK_PROTOCOL.md) defines envelopes, actions, payloads, results/events, validation, phase limits, rate limits, and idempotency. |
| State machines locked | **PASS** | [STATE_MACHINES.md](docs/STATE_MACHINES.md) defines Raid, theft, mutation, and Welcome transitions and edge handling. |
| Test matrix ready | **PASS** | [TESTING.md](docs/TESTING.md) maps deterministic unit, integration, persistence, security, and Studio coverage to milestones. |
| M0–M12 actionable | **PASS** | [MILESTONES.md](docs/MILESTONES.md) defines scope, non-goals, dependencies, player result, tests, acceptance, docs, and commit boundary for each. |
| Toolchain verified | **PASS** | Pinned versions match; `./scripts/verify.ps1` passed; all seven project skills passed the bundled validator; Markdown links resolve. |
| Rojo build | **PASS** | `default.project.json` built to the ignored `build/foundation.rbxlx`. |
| Rojo serve | **PASS** | `./scripts/serve.ps1` listened on `localhost:34872`; local HTTP returned 200; process stopped after verification. |
| Studio installed / login known | **BLOCKED** | Studio was not detected in the inspected install paths or Appx packages, so login cannot be checked. |
| Rojo Studio plugin sync | **BLOCKED** | Cannot verify without Studio. Plugin connection workflow is documented in [tests/multiplayer/README.md](tests/multiplayer/README.md). |
| Two-client M0 smoke | **BLOCKED** | Requires the human Studio install/sign-in and Rojo plugin connection. Lune tests do not simulate multiplayer. |
| Git clean and remote synchronized | **PASS** | `main` pushed to the confirmed `abdulrahmansad/roblox` origin; remote `main` matches local HEAD; worktree clean. |

## Remaining human action

Install Roblox Studio, sign in, install the Rojo 7 Studio plugin, then open this repository in Studio, run `./scripts/serve.ps1`, connect the plugin to `localhost:34872`, and complete the documented two-client M0 smoke.

## Verdict

**NOT READY TO BUILD** — all repository, design, documentation, CLI, Rojo CLI, and Git gates pass. M0 Studio/plugin/two-client validation remains a prerequisite and needs the human action above.
