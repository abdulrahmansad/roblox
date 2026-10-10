# Build start checklist

V1 pre-build readiness review is complete. M1 and M2 foundation code is already committed; this readiness phase changes documentation only. The implementation branch is ready to resume at M3 after the documented Studio-only M0/M1/M2 checks are completed.

| Gate | Status | Evidence |
| --- | --- | --- |
| V1 design frozen | **PASS** | [GAME_DESIGN.md](docs/GAME_DESIGN.md) marks the approved V1 specification as frozen. |
| Final Welcome protection correction | **PASS** | [RAIDS.md](docs/RAIDS.md), [DATA_MODEL.md](docs/DATA_MODEL.md), [STATE_MACHINES.md](docs/STATE_MACHINES.md), and [SECURITY.md](docs/SECURITY.md) define the durable first-participation marker and strict grace boundary. |
| Architecture locked | **PASS — SPECIFICATION** | [ARCHITECTURE.md](docs/ARCHITECTURE.md) assigns server services, shared contracts, and presentation-only client controllers. |
| Data model locked | **PASS — SPECIFICATION** | [DATA_MODEL.md](docs/DATA_MODEL.md) specifies schema, defaults, migrations, validation, corruption handling, and runtime-only state. |
| Network protocol locked | **PASS — SPECIFICATION** | [NETWORK_PROTOCOL.md](docs/NETWORK_PROTOCOL.md) defines actions, payloads, phases, validation, throttles, idempotency, events, and errors. |
| State machines locked | **PASS — SPECIFICATION** | [STATE_MACHINES.md](docs/STATE_MACHINES.md) defines Raid, theft, mutation, and Welcome protection transitions. |
| Test matrix ready | **PASS — SPECIFICATION** | [TESTING.md](docs/TESTING.md) covers capsule, mutation, Raid, Welcome protection, theft, Tag, persistence, protocol, Studio, and monetization. |
| M0–M12 ready | **PASS — SPECIFICATION** | [MILESTONES.md](docs/MILESTONES.md) defines scope, non-goals, dependencies, results, tests, acceptance, docs, and commit boundaries. |
| Toolchain | **PASS** | Pinned tools match; `./scripts/verify.ps1` passes format, lint (0 warnings/errors), 24 portable tests, and Rojo build. PowerShell scripts and pinned versions were checked. No skill-specific validator is supplied in the repository. |
| Rojo configuration/build | **PASS** | `default.project.json` builds successfully. |
| Rojo serve workflow | **PASS** | `./scripts/serve.ps1` served `127.0.0.1:34872` with HTTP 200; the process was stopped after checking. Connection and two-client steps are documented in [tests/multiplayer/README.md](tests/multiplayer/README.md). |
| Studio status | **KNOWN — HUMAN CHECK PENDING** | Roblox Studio is not installed in the inspected locations; sign-in cannot be checked and the Rojo plugin cannot be verified. No Studio success is claimed. |
| Existing M1/M2 implementation | **PORTABLE PASS; STUDIO PENDING** | Session/base, profile persistence, and online income are committed on `main`; engine-backed and live DataStore checks remain pending. |
| M3–M12 | **READY TO IMPLEMENT; NOT ON `main`** | Milestones are specified; no later milestone is included in the branch. |
| Git | **PASS AFTER READINESS PUSH** | `main` points to `abdulrahmansad/roblox`; the readiness commit must be pushed and verified against `origin/main` before marking synchronized. |

The pre-existing uncommitted M3 work was preserved in the local stash `paused M3 gameplay during pre-build readiness`; it is excluded from `main` and from this readiness commit.

## Human-only action

Install and sign in to Roblox Studio, install the Rojo 7 plugin, connect it to `localhost:34872`, then run the M0 two-client smoke and the M1/M2 Studio checks in [tests/multiplayer/README.md](tests/multiplayer/README.md), including live DataStore/API-services and leaderboard behavior.

## Verdict

**READY TO BUILD** — the design and implementation contracts are locked, portable checks pass, and the remaining Studio-only step is explicit.
