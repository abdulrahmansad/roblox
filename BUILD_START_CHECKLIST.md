# Build and release readiness checklist

The V1 design and architecture are locked. M1–M9 portable implementation is complete. M10's portable diagnostics, log summarization, and hostile-review slice passes, but M10 is not accepted because its empirical Studio playtest gates remain unverified. The approved design remains frozen.

| Gate | Status | Evidence |
| --- | --- | --- |
| V1 design, architecture, data model, protocol, and state machines | **LOCKED** | `docs/GAME_DESIGN.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/NETWORK_PROTOCOL.md`, and `docs/STATE_MACHINES.md`. |
| M1–M9 local implementation | **PORTABLE PASS; STUDIO PENDING** | Milestone records in `docs/PROJECT_STATUS.md`; all remain in the current regression suite. |
| M10 local hostile review and diagnostics | **PORTABLE PASS; PLAYTEST PENDING** | Current `./scripts/verify.ps1`: formatting, Selene (0 issues), 87 Lune tests, playtest-summary fixture checks, and Rojo build. Local event tests cover server-derived progression/economy/theft events, replay safety, and strict grace eligibility. |
| M10 balance and release gates | **NOT ACCEPTED** | First-session timing, loss-driven exits, phone/tablet usability, 2-client races, 6–8-client behavior, persistence integration, and device performance require Studio playtests. No balance adjustment is justified without this evidence. |
| M11 Curator's Palette | **GATED** | Begins only after M10 gameplay gates pass; Creator Hub pass creation and entitlement validation require the development account. No product ID or pass code has been created. |
| M12 release readiness | **PREPARATION ONLY** | Checklist below is unsigned. M12 depends on M7–M11 acceptance, live persistence, support ownership, current platform/account review, and rollback rehearsal. |
| Rojo configuration/build | **PASS** | `default.project.json` builds through the canonical verification script. |
| Git | **SAFE STATE** | Verified M10 telemetry commit `0784779c81303cbe31062b7c941984c1cfa0b1aa` and the offline playtest-summary slice are pushed to `origin/main`; no force push or history rewrite was used. |
| Studio status | **HUMAN CHECK REQUIRED** | Studio was rechecked during M10 and remains absent from process, PATH, and inspected install locations. No Studio, device, multiplayer, or live DataStore success is claimed. |

## Human action to unblock M10

1. Install and sign in to Roblox Studio on this machine, then install the Rojo 7 Studio plugin.
2. From the repository root, run `./scripts/serve.ps1` and connect the plugin to `localhost:34872`.
3. Follow [tests/multiplayer/README.md](tests/multiplayer/README.md): run the 2-client interaction/race scenarios, then 6–8-client join/leave checks; use representative phone/tablet emulation; save server Output containing `[OddlingsAnalytics]` lines to `C:\playtest\server-output.txt` and summarize it with `./scripts/summarize-playtest.ps1 -Path C:\playtest\server-output.txt`. Review the summary with observer notes; it reports metrics but does not make qualitative gate decisions.
4. Use a safe test experience/store for live persistence validation. Do not connect Studio testing to production player data.
5. Return the playtest results and any console errors. The local canonical command to rerun afterward is `./scripts/verify.ps1`.

After M10 is accepted, M11 requires the account owner to create the approved 99 Robux Curator's Palette pass in Creator Hub and provide its product ID for server-side configuration and entitlement testing. Public publishing remains a separate action and is not authorized by this checklist.

## M12 release checklist — prepared, not signed off

- [ ] M0–M11 acceptance evidence is current and all full local verification is green.
- [ ] Studio smoke, 2-client race/security checks, and 6–8-client load/join/leave checks pass.
- [ ] Phone and tablet checks pass for readability, 52 px controls, holds, reduced effects, and audio alternatives.
- [ ] Live persistence load/save, session conflict, retry, shutdown, backup restore, and theft journal recovery are validated against a safe test store.
- [ ] No open Critical or High gameplay, authority, theft, or data-integrity issue remains.
- [ ] Moderation, privacy, support/debugging, and current Creator Hub/platform requirements are reviewed.
- [ ] Performance evidence covers low-end hardware, memory, instance count, network volume, connection cleanup, and 6–8 players.
- [ ] Balance evidence satisfies the gates in `docs/MVP.md`, including first capsule/Raid timing and loss-driven exits.
- [ ] Cosmetic pass entitlement is verified server-side and has no gameplay, visibility, capacity, or raid effect.
- [ ] Release candidate commit, rollback revision/procedure, and support owner are recorded.
- [ ] Public release decision is reviewed and explicitly authorized separately.

**Current verdict: NOT READY FOR RELEASE.** M10 empirical gates are open; M11 and M12 are not accepted.
