# Build progress checklist

V1 implementation is underway. This checklist tracks the original build gates and current milestone state; it does not claim release readiness.

| Gate | Status | Evidence |
| --- | --- | --- |
| V1 design frozen | **PASS** | [GAME_DESIGN.md](docs/GAME_DESIGN.md) and approved V1 scope. |
| Welcome protection rule locked | **PASS** | [RAIDS.md](docs/RAIDS.md), [DATA_MODEL.md](docs/DATA_MODEL.md). |
| Architecture, data, network, state machines | **PASS — SPECIFICATION** | [ARCHITECTURE.md](docs/ARCHITECTURE.md), [DATA_MODEL.md](docs/DATA_MODEL.md), [NETWORK_PROTOCOL.md](docs/NETWORK_PROTOCOL.md), [STATE_MACHINES.md](docs/STATE_MACHINES.md). Runtime implementations are still pending by milestone. |
| Test matrix and M0–M12 plan | **PASS — SPECIFICATION** | [TESTING.md](docs/TESTING.md), [MILESTONES.md](docs/MILESTONES.md). |
| M0 CLI verification | **PASS** | Pinned tools match; `./scripts/verify.ps1` passes; `./scripts/serve.ps1` listens on `localhost:34872` and returns HTTP 200. |
| M0 Studio/plugin/two-client smoke | **BLOCKED** | Roblox Studio is not installed; sign-in and Rojo plugin connection cannot be checked. |
| M1 session/base implementation | **CODE PASS; STUDIO PENDING** | Eight-base assignment, character relocation, session cleanup, phase snapshot inheritance; portable tests and Rojo build pass. |
| M2 starter/profile/online income | **CODE PASS; STUDIO PENDING** | Schema, DataStore session lease, retries, and income implemented; fake-store tests pass. Live DataStore/API-services check remains. |
| M3–M12 | **NOT STARTED** | See current milestone and remaining work in [PROJECT_STATUS.md](docs/PROJECT_STATUS.md). |
| Git | **PASS AFTER M2 PUSH** | M1 is pushed; M2 is committed to `main`, pushed to the configured origin, and local `main` matches remote. |

## Remaining human action

Install and sign in to Roblox Studio, install the Rojo 7 plugin, connect to `localhost:34872`, and run the documented M0/M1 two-client smoke and M2 live DataStore/leaderboard checks. These Studio-dependent acceptance items remain pending while independent milestones continue.

## Current verdict

**BUILD IN PROGRESS — NOT READY** for a complete playable V1. M1 and M2 have portable local evidence; Studio validation and M3–M12 remain.
