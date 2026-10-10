---
name: roblox-rojo-workflow
description: Configure source mappings, dependencies, live sync, or place builds with Rojo and Wally in this repository.
---

# Roblox Rojo workflow

The filesystem is the source of truth. Read [tooling](../../../docs/TOOLING.md) and inspect `default.project.json` and `rokit.toml` before changing the toolchain. Pin tool changes in the manifest, keep generated Wally folders and builds ignored, and do not add Studio-only source.

Run `./scripts/setup.ps1` when dependencies change and `./scripts/verify.ps1` after mapping changes. Studio live sync uses the matching Rojo 7 plugin at `localhost:34872`.
