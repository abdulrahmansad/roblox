# Build start checklist

V1 pre-build readiness is complete, and the V1 build is now in progress. M1 and M2 are committed. M3's portable implementation and verification pass are complete; Studio checks remain pending while work proceeds to M4.

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
| Toolchain | **PASS** | Pinned tools match; current `./scripts/verify.ps1` passes format, lint (0 warnings/errors), 37 portable tests, and Rojo build. PowerShell scripts and pinned versions were checked. No skill-specific validator is supplied in the repository. |
| Rojo configuration/build | **PASS** | `default.project.json` builds successfully. |
| Rojo serve workflow | **PASS** | `./scripts/serve.ps1` served `127.0.0.1:34872` with HTTP 200; the process was stopped after checking. Connection and two-client steps are documented in [tests/multiplayer/README.md](tests/multiplayer/README.md). |
| Studio status | **KNOWN — HUMAN CHECK PENDING** | Roblox Studio is not installed in the inspected locations; sign-in cannot be checked and the Rojo plugin cannot be verified. No Studio success is claimed. |
| Existing M1/M2 implementation | **PORTABLE PASS; STUDIO PENDING** | Session/base, profile persistence, and online income are committed on `main`; engine-backed and live DataStore checks remain pending. |
| M3 | **PORTABLE PASS; STUDIO PENDING** | Capsule, creature, sale, slot, stand projection, and centralized action code pass the 37-test suite and Rojo build. Studio kiosk and visual stand checks remain pending. |
| M4–M12 | **READY TO IMPLEMENT; NOT STARTED** | Remaining milestone scopes and acceptance gates are specified in `docs/MILESTONES.md`. |
| Git | **M3 COMMIT/PUSH IN PROGRESS** | The readiness baseline was synchronized at `92294325f9c44aa038cccd8cf9bb068be5526611`; M3 changes are being closed in a focused commit and will be synchronized before M4. |

Historical copies of the paused M3 work remain in the local stashes; the active M3 implementation has been restored to the worktree for completion.

## Human-only action

Install and sign in to Roblox Studio, install the Rojo 7 plugin, connect it to `localhost:34872`, then run the M0 two-client smoke, M1/M2 join/DataStore checks, and M3 kiosk/stand interaction smoke in [tests/multiplayer/README.md](tests/multiplayer/README.md).

## Verdict

**BUILD IN PROGRESS** — the locked V1 plan is being implemented milestone by milestone. Studio-only checks remain explicit and do not block portable M4 work.
