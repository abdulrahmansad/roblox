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

## Prepared incident and rollback runbook — not rehearsed

This procedure is ready for a named release owner to adopt. No public release or rollback has been performed.

### Before any release

- Record the release Git commit, successful verification output, Rojo build, private Studio result, and matching saved/published place version in one release note.
- Save Roblox place checkpoints with version notes so the last known-good version is identifiable in [Roblox Version History](https://create.roblox.com/docs/projects/version-history).
- Name one support/release owner and an account backup who can access the experience and its version history. Record names and private contact details outside this repository.
- Keep an isolated test experience/store for Studio and persistence checks. Never point a test place at production player data.
- Complete the current Roblox Maturity & Compliance Questionnaire accurately before a public release and review Roblox's [safety guidance](https://create.roblox.com/docs/safety). V1 adds no custom user-created content or trading system; confirm final platform chat settings, review the fixed theft/chase loop for abuse reports, and make the player-facing rules understandable without adding unapproved gameplay systems.

### Incident intake and triage

1. Record UTC time, place/version, Git commit, server/client context, observed behavior, exact reproduction steps, severity, and whether progression may be affected.
2. Treat suspected duplication, permanent loss, client-authority bypass, or broad service failure as release-stopping. Stop further rollout and preserve the private test evidence before changing code or data.
3. Keep raw Roblox logs, account/player identifiers, and private contact details in access-controlled support records, never in Git issues or committed fixtures. The local playtest summary omits session tokens; it is diagnostic evidence, not a player support record.
4. For an isolated UI/audio issue, record device, viewport, input method, and reproduction. For a safety report, preserve the minimum evidence needed and use the account owner's Roblox moderation/reporting workflow.
5. Assign an owner and next review time; close an incident only after a verified fix or documented disposition.

### Rollback procedure

1. Identify the last known-good Git commit and matching Roblox place version from the release note. Confirm whether the failure is in source, the published place, or persisted player data; a code rollback does not reverse saved player data.
2. For a source regression, create a new `git revert` commit on the release branch (never rewrite or force-push published history), run `./scripts/verify.ps1`, rebuild with Rojo, and validate the reverted build in a private Studio session.
3. For a published place regression, the account owner restores the recorded place version through Studio or Creator Dashboard Version History. Roblox documents that restore creates a new place version and does not publish it automatically; if the experience is public, the owner must separately publish the restored version and restart servers. Do not perform this account-side action without the separately authorized release decision.
4. If persisted data may be affected, do not overwrite profiles or assume a place rollback restores player data. Freeze writes to the affected test and preserve version/time evidence. Use M7 transfer-journal replay only for an in-progress theft; wait for a separately reviewed DataStore recovery plan before resuming other writes.
5. Run the server/client smoke, persistence checks, and affected regression cases in the private test place; record the result, restored place version, and follow-up owner. Reopen a public rollout only after explicit release-owner approval.

**Current verdict: NOT READY FOR RELEASE.** M10 empirical gates are open; M11 and M12 are not accepted.
