# Studio multiplayer test foundation

Roblox Studio's **Server & Clients** mode supports up to eight simulated clients. Use 2 clients for interaction and race checks, then increase to 6–8 for join/leave and load scenarios only when the test machine has enough memory headroom. Studio is required; local Lune tests do not claim to simulate multiplayer.

## Memory-constrained test workflow

1. Run `./scripts/verify.ps1` first; its portable tests and Rojo build do not require a Studio Play session.
2. Keep one project open in Studio and leave it in Edit mode between checks. Stop each Play session before starting another.
3. Check Task Manager's **Performance > Memory > Available** before starting Play. If less than 1 GiB is available, do not start a Studio Play session. If less than 2 GiB is available, defer 2-client and larger runs. These are conservative operating guardrails, not acceptance criteria or a substitute for recording the test result.
4. Do not start 6–8-client load checks on a machine that is already paging heavily or has less than 2 GiB available. Move those checks to a better-equipped test machine if necessary; keep the Studio gates marked pending until they run.

The current development laptop exposes 5.85 GiB of physical memory to Windows and had 0.13–0.29 GiB available after the one-client smoke. Windows automatic paging is enabled, but disk paging is much slower than physical memory and does not make multiplayer Studio tests safe under low headroom. Lenovo identifies this device as IdeaPad 1 15ALC7 (Type 82R4); its PSREF lists one soldered memory module plus one DDR4 SO-DIMM slot and up to 16 GB total. A compatible 8 GB DDR4-3200 SO-DIMM is the supported upgrade path for this configuration; confirm the exact machine SKU with Lenovo before buying. See [Lenovo PSREF](https://psref.lenovo.com/Product/IdeaPad/IdeaPad_1_15ALC7?MT=82R4).

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

Unpublished Studio server/client tests use Studio's negative local `UserId` values. The server maps those IDs to temporary profile keys only while the unpublished-place in-memory datastore adapter is active. This lets the normal session, base, and Raid snapshot paths run locally; the keys never reach Roblox's persistent datastores or published servers. On 2026-10-12, two local clients joined after this mapping fix. Separately focused views showed distinct profile balances (810 and 623 Scrap), different local Ember/Prism tutorial choices, and Peace countdowns within four seconds. This startup smoke does not cover a server-owned gameplay action.

Roblox also documents `StudioTestService` for plugin-driven multiplayer test sessions, adding players mid-test, disconnecting clients, and ending a test from the server. M5–M9 gameplay scenarios now exist, but an automated Studio plugin harness has not been added. Use the manual scenarios below; keep Studio multiplayer coverage marked pending until a session actually runs.

## M5 Raid clock and arrival grace

After starting a two-client session, confirm both clients show the same phase and countdown. Join a second client during RAID and confirm the shared timer does not reset; its 15-second arrival-grace label begins only after its character and base are ready, then disappears at expiry or when RAID ends. Reset the joining client's character and confirm the grace deadline does not move. Verify players joining in PEACE/WARNING receive no grace. Repeat with a late RAID join whose grace would outlast the RAID and confirm the next phase is shown at the shared boundary. The portable suite covers exact second boundaries; use Studio only for replicated attributes, UI timing, and multiplayer lifecycle behavior.

## M8 onboarding and mobile presentation

After syncing with Rojo, use Studio's Device Simulator at representative phone sizes such as 360×800 and 390×844, plus short landscape sizes such as 800×360 and 844×390. Rotate while the Commons panel is open and confirm its title, Close control, and action rows stay visible. Confirm the phase/economy HUD, one goal card, theme choice, commerce/mutation panel, and contextual action control fit without covering the main interaction area. Check that primary controls are at least 52 px tall, readable with touch, and usable without precision aiming. Verify the hold ring advances for theft, bank, and recovery; theft cancels on early release, while bank/recovery progress resets after movement beyond the server's 0.5-stud stationary tolerance. Check keyboard E/Q and touch behavior for the same contextual actions.

With two clients, complete the free mutation and Welcome flow, then exercise a theft channel, early release, carry, Tag/drop, owner recovery, and bank. Confirm captions explain important events even when audio is muted. Inspect the recovery marker on the owner and thief clients and confirm a third client never receives the target position. Repeat with a client joining during RAID and confirm grace is visible without changing the shared countdown. Portable tests cover the server-side rules and event privacy. The first two-client attempt crashed with graphics driver error `0x887a0020` (`OutOfMemoryGraphics`); after adding unpublished-Studio identity mapping, both clients joined and showed independent tutorial choices. Completing the mutation, Welcome purchase, theft/Tag/recovery interactions, late-join grace, and third-client privacy checks remains pending.

Additional scenarios still to execute in Studio: two-player interaction, ownership and proximity checks, duplicate/replayed requests, disconnect during interaction, race conditions, dropped items, join during an event, and 6–8-client mobile performance.

## M10 playtest evidence

For controlled private sessions, save the server Output containing `[OddlingsAnalytics]` records to `C:\playtest\server-output.txt`. From the repository root, run `./scripts/summarize-playtest.ps1 -Path C:\playtest\server-output.txt > C:\playtest\summary.json` and save the JSON summary with the session notes. The summary omits session identifiers and reports progression timing, economy totals, Raid/grace outcomes, theft protection, Tag/recovery, and loss-to-exit measurements. It is descriptive evidence, not an automatic pass/fail judgment. Keep captured logs local to the private playtest and do not include account or player identifiers in observer notes.
