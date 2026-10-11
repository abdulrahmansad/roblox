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

## M5 Raid clock and arrival grace

After starting a two-client session, confirm both clients show the same phase and countdown. Join a second client during RAID and confirm the shared timer does not reset; its 15-second arrival-grace label begins only after its character and base are ready, then disappears at expiry or when RAID ends. Reset the joining client's character and confirm the grace deadline does not move. Verify players joining in PEACE/WARNING receive no grace. Repeat with a late RAID join whose grace would outlast the RAID and confirm the next phase is shown at the shared boundary. The portable suite covers exact second boundaries; use Studio only for replicated attributes, UI timing, and multiplayer lifecycle behavior.

## M8 onboarding and mobile presentation

After syncing with Rojo, use Studio's device emulator at representative phone sizes such as 360×800 and 390×844. Confirm the phase/economy HUD, one goal card, theme choice, commerce/mutation panel, and contextual action control fit without covering the main interaction area. Check that primary controls are at least 52 px tall, readable with touch, and usable without precision aiming. Verify the hold ring advances for theft, bank, and recovery; theft cancels on early release, while bank/recovery progress resets after movement beyond the server's 0.5-stud stationary tolerance. Check keyboard E/Q and touch behavior for the same contextual actions.

With two clients, complete the free mutation and Welcome flow, then exercise a theft channel, early release, carry, Tag/drop, owner recovery, and bank. Confirm captions explain important events even when audio is muted. Inspect the recovery marker on the owner and thief clients and confirm a third client never receives the target position. Repeat with a client joining during RAID and confirm grace is visible without changing the shared countdown. Portable tests cover the server-side rules and event privacy. Studio is installed and connected, and the unpublished local server starts using the explicit volatile store. Two local test clients crashed with graphics driver error `0x887a0020` (`OutOfMemoryGraphics`) before joining, so these checks remain pending.

Future scenarios: two-player interaction, ownership and proximity checks, duplicate/replayed requests, disconnect during interaction, race conditions, dropped items, join during an event, and 6–8-client mobile performance.

## M10 playtest evidence

For controlled private sessions, save the server Output containing `[OddlingsAnalytics]` records to `C:\playtest\server-output.txt`. From the repository root, run `./scripts/summarize-playtest.ps1 -Path C:\playtest\server-output.txt > C:\playtest\summary.json` and save the JSON summary with the session notes. The summary omits session identifiers and reports progression timing, economy totals, Raid/grace outcomes, theft protection, Tag/recovery, and loss-to-exit measurements. It is descriptive evidence, not an automatic pass/fail judgment. Keep captured logs local to the private playtest and do not include account or player identifiers in observer notes.
