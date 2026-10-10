# Agent operating rules

Before changing files, read this document and the relevant material in `docs/`. Inspect the current branch, worktree status, tool versions, scripts, and nearby code first.

When a task matches a project skill under `.agents/skills/`, read that skill as well as its linked domain documentation.

## Required workflow

1. Keep changes within the requested scope and work in small, reviewable slices.
2. Preserve the architecture described in `docs/ARCHITECTURE.md`.
3. Keep the server authoritative. Treat every client request as untrusted and validate it at the server boundary.
4. Keep network declarations centralized in `src/shared/network`; do not create remotes ad hoc in gameplay modules.
5. Put presentation in client code and decisions or ownership in server code.
6. Add or update meaningful tests for behavior changes. Never delete or weaken tests to make a check pass.
7. Run formatting, lint, tests, and the Rojo build using `./scripts/verify.ps1`; fix failures and rerun it.
8. Update documentation and `docs/PROJECT_STATUS.md` when reality changes.
9. Report validation results and any Studio/account-dependent blocker accurately.

## Do not

- Claim completion without running and reporting applicable validation.
- Trust client-provided currency, rewards, ownership, rarity, mutation outcomes, purchases, raid results, or save data.
- Add dependencies without a clear need or change pinned tool versions casually.
- introduce full gameplay systems, feature frameworks, or design decisions outside the task.
- Ignore failures, remove tests to pass CI, or perform broad rewrites without need.

## Scope guard

This is a development foundation. The approved high-level concept is in `docs/GAME_DESIGN.md`; **FULL GAME DESIGN WILL BE LOCKED IN A LATER PHASE.** Do not expand the concept during foundation work.
