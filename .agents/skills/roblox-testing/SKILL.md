---
name: roblox-testing
description: Add or run Luau unit, server integration, security, persistence, monetization, or Studio multiplayer tests for this repository.
---

# Roblox testing

Read [testing guidance](../../../docs/TESTING.md). Use Lune for portable tests, TestEZ for Roblox-engine tests, and Studio for client/server or multiplayer behavior. Studio supports up to eight simulated clients; never claim a local test simulates multiplayer.

Keep tests meaningful and run `./scripts/verify.ps1`. Document any Studio-only check that could not run.
