# Build start checklist

V1 pre-build readiness is complete, and the V1 build is now in progress. M1–M3 are committed and pushed. M4's portable implementation and verification pass are complete; Studio checks remain pending.

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
| Toolchain | **PASS** | Pinned tools match; current `./scripts/verify.ps1` passes format, lint (0 warnings/errors), 48 portable tests, and Rojo build. PowerShell scripts and pinned versions were checked. No skill-specific validator is supplied in the repository. |
| Rojo configuration/build | **PASS** | `default.project.json` builds successfully. |
| Rojo serve workflow | **PASS** | `./scripts/serve.ps1` served `127.0.0.1:34872` with HTTP 200; the process was stopped after checking. Connection and two-client steps are documented in [tests/multiplayer/README.md](tests/multiplayer/README.md). |
| Studio status | **KNOWN — HUMAN CHECK PENDING** | Roblox Studio is not installed in the inspected locations; sign-in cannot be checked and the Rojo plugin cannot be verified. No Studio success is claimed. |
| Existing M1/M2 implementation | **PORTABLE PASS; STUDIO PENDING** | Session/base, profile persistence, and online income are committed on `main`; engine-backed and live DataStore checks remain pending. |
| M3 | **PORTABLE PASS; STUDIO PENDING** | Capsule, creature, sale, slot, stand projection, and centralized action code pass the 37-test suite and Rojo build. Studio kiosk and visual stand checks remain pending. |
| M4 | **PORTABLE PASS; STUDIO PENDING** | Mutation catalog, catalyst/tutorial/normal roll services, choices, pity, locks, and protocol pass 48 tests and Rojo build. Studio station checks remain pending. |
| M5–M12 | **READY TO IMPLEMENT** | Remaining milestone scopes and acceptance gates are specified in `docs/MILESTONES.md`. |
| Git | **M4 COMMIT/PUSH IN PROGRESS** | `main` and `origin/main` are at the M4 kickoff documentation commit `dc446504775306610110fc35b93e894c1556f017`; M4 code is locally verified and closing in a focused milestone commit. |

Historical copies of the paused M3 work remain in local stashes after the M3 implementation was committed.

## Human-only action

Install and sign in to Roblox Studio, install the Rojo 7 plugin, connect it to `localhost:34872`, then run the M0 two-client smoke, M1/M2 join/DataStore checks, M3 kiosk/stand smoke, and M4 mutation-station checks in [tests/multiplayer/README.md](tests/multiplayer/README.md).

## Verdict

**BUILD IN PROGRESS** — the locked V1 plan is being implemented milestone by milestone. Studio-only checks remain explicit and do not block portable M4 work.
