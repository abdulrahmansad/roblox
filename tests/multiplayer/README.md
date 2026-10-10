# Studio multiplayer test foundation

Roblox Studio's **Server & Clients** mode supports up to eight simulated clients. Use 2 clients for interaction and race checks, then increase to 6–8 for join/leave and load scenarios. Studio is required; local Lune tests do not claim to simulate multiplayer.

Current manual smoke:

1. Open the Roblox place/project in Studio and sign in to the Roblox account used for development.
2. From the repository root, run `./scripts/serve.ps1`; it serves `default.project.json` on `127.0.0.1:34872`.
3. Open the Rojo 7 Studio plugin and connect to `localhost:34872`. Wait for sync to finish and check the Output window for sync errors.
4. In Studio, choose **Test > Server & Clients**, set 2 clients, and start a session.
5. Confirm the server prints `[Foundation] Server initialized...` and each client prints that its ping was accepted.
6. In the Studio command bar with **Client** context selected, run:

   ```lua
   local ping = game:GetService("ReplicatedStorage").Network.DevPing
   print(ping:InvokeServer({ requestId = "m0-valid" }))
   print(ping:InvokeServer({ requestId = "m0-invalid", currency = 1 }))
   ```

   The first response must have `accepted = true`; the second must have `accepted = false` and reason `MalformedRequest`. Do not expose debug exploit controls to published clients.

Roblox currently also documents `StudioTestService` for plugin-driven multiplayer test sessions, adding players mid-test, disconnecting clients, and ending a test from the server. Add an automated Studio plugin harness when gameplay scenarios exist; there is no gameplay to exercise yet.

Future scenarios: two-player interaction, phase transitions, ownership and proximity checks, duplicate/replayed requests, disconnect during interaction, race conditions, dropped items, join during an event, and 6–8-player mobile performance.
