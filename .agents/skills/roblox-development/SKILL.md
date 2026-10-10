---
name: roblox-development
description: Implement or revise Roblox gameplay and runtime code in this repository while preserving its client, server, and shared boundaries.
---

# Roblox development

Read `AGENTS.md` and [architecture](../../../docs/ARCHITECTURE.md) first. Keep client code presentational, shared code deterministic, and all ownership or progression decisions server-side. Avoid adding features outside the approved request and current game-design scope.

For changes, add behavior-focused tests, then run `./scripts/verify.ps1` and update the relevant docs.
