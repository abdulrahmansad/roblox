# Studio multiplayer test foundation

Roblox Studio's **Server & Clients** mode supports up to eight simulated clients. Use 2 clients for interaction and race checks, then increase to 6–8 for join/leave and load scenarios. Studio is required; local Lune tests do not claim to simulate multiplayer.

Current manual smoke:

1. Start Rojo and connect the Rojo 7 plugin.
2. In Studio, choose **Server & Clients** with 2 clients and start a session.
3. Confirm the server prints `[Foundation] Server initialized...` and each client prints that its ping was accepted.
4. Exercise malformed payload rejection through a future test harness. Do not expose debug exploit controls to published clients.

Roblox currently also documents `StudioTestService` for plugin-driven multiplayer test sessions, adding players mid-test, disconnecting clients, and ending a test from the server. Add an automated Studio plugin harness when gameplay scenarios exist; there is no gameplay to exercise yet.

Future scenarios: two-player interaction, phase transitions, ownership and proximity checks, duplicate/replayed requests, disconnect during interaction, race conditions, dropped items, join during an event, and 6–8-player mobile performance.
