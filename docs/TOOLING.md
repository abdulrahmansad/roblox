# Tooling

Project CLI versions are pinned in `rokit.toml`: Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, and Lune 0.10.5. Rokit itself is installed per user; setup requires Rokit 1.2.0 or newer. Keep tool updates deliberate and review the generated manifest changes.

Wally's TestEZ 0.4.1 development dependency is locked in `wally.lock`; package source is generated into ignored `DevPackages/` and mapped only under server storage. Do not add runtime packages until a feature needs them.

StyLua uses `stylua.toml`; Selene uses `selene.toml` and Roblox/TestEZ standard libraries. PowerShell scripts are the supported Windows command interface. Rojo Studio sync requires the matching Rojo 7 Studio plugin, installed from the official Rojo guide; no unrelated plugins are required.
