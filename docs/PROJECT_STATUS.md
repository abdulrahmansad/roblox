# Project status

Status: development foundation initialized; full game design and gameplay remain out of scope.

- Repository rules, source mapping, pinned CLI manifest, scripts, foundation documentation, and seven repo-local Roblox skills are in place.
- The smoke path demonstrates a server-validated request with a portable Lune test suite and a Roblox TestEZ spec.
- Local verification status: passed; format, lint, four tests, and Rojo build all succeeded.
- Roblox Studio status: not detected in Program Files, LocalAppData, or AppX packages. `rojo plugin install` confirmed Roblox registry keys are absent. Human action: install Studio from Roblox Creator Hub, sign in once, then run `rojo plugin install` and execute the documented two-client smoke test.
- Git status: initial branch is `main`; origin is configured, but the remote currently has no reachable refs and this repository has no commits.
