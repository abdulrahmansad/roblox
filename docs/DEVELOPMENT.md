# Development workflow

1. Read `AGENTS.md` and relevant docs; inspect Git status before editing.
2. Run `./scripts/setup.ps1` once, then `./scripts/verify.ps1` before submitting changes.
3. Keep code in the matching shared/server/client boundary. Keep gameplay decisions on the server.
4. Add real tests and update documentation with behavior changes.
5. Use `./scripts/serve.ps1` and the Rojo Studio plugin for live sync. Studio login is required for Studio testing.
6. Review the diff and report commands, results, and any external blocker accurately.

Never commit credentials, generated builds, caches, or Wally's generated `DevPackages` directory. Keep `rokit.toml` and `wally.lock` committed so tool and dependency resolution stays reproducible.
