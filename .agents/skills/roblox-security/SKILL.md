---
name: roblox-security
description: Design or review Roblox remotes, authoritative state, persistence, entitlements, or other trust boundaries in this repository.
---

# Roblox security

Read `AGENTS.md` and [security rules](../../../docs/SECURITY.md). Treat replicated code and every client payload as public and untrusted. Validate payload shape, identity, state, ownership, proximity, cooldown, frequency, replay, and permissions at the server boundary as applicable. Keep rewards, saved data, and purchase fulfillment server-authoritative.

Add rejection tests for the relevant abuse case. Do not treat Luau types or client checks as security controls.
