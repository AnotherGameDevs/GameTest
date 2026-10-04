# In-engine test plan (nothing below has been run — this environment has no Roblox Studio)

Setup: open `Build/DigAndRun.rbxlx` in Studio (or `rojo serve` + Connect). Test > Server + 2 Players for the multiplayer
rows. Open View > Output; Studio sessions print `[Metrics]` once a minute.
Fresh profile: Studio has no DataStore unless the place is published and *Studio Access to API Services* is on; without
it every session starts fresh (expected, a warning is printed). **Do not enable Studio API access on the production place.**

| # | Test | Expected | Result |
|---|------|----------|--------|
| 1 | Spawn | land on camp, nothing under feet but the floor; mine visible ahead ~40 studs | untested |
| 2 | First-time hints | "DIG" card at start, gone after ~4 blocks; backpack/sell/upgrade/elevator/artifact/collection cards in order; none over the crosshair | untested |
| 3 | Dig loop | hold click: highlight = hit block; out-of-reach shows "TOO FAR"; stone with Rusty shows "TOO HARD - needs the Heavy Shovel" | untested |
| 4 | Sell, buy, equip | walk into gold disc sells; shop opens only near the stall; buying Digging Shovel equips it, swing rate visibly faster | untested |
| 5 | Backpack | fills, "BACKPACK FULL", sell empties; buy Big Satchel, capacity 30 | untested |
| 6 | Menus | repeat: P, shop, J, Alt, Esc (Roblox menu) in all orders; cursor frees/locks correctly, no held mining afterwards, prior mode restored | untested |
| 7 | Focus loss / death / respawn / tool switch | alt-tab while holding click; reset character; equip another tool: no stuck mining | untested |
| 8 | Artifact | reach Ruins (needs Jackhammer; or temporarily edit `MinToolTier`), pick up an Epic, try: dig (blocked), R (blocked + message), switch tool (blocked), place (X), pick up again, elevator up, deposit once; cash +value once; collection entry appears only now | untested |
| 9 | Death / leave while carrying | artifact dropped where you stood or on Lost & Found; rejoin same server: can pick up again | untested |
| 10 | Journal + shelf | J opens; put 2 entries on shelf; shelf at west camp shows them; second player sees none of yours | untested |
| 11 | Persistence | leave and rejoin a published test place: cash, tools, equipped, collection, shelf, settings, hint progress restored | untested |
| 12 | Failed load | simulate DataStore failure (offline Studio API): in a published server the player is kicked with a message, nothing saved over their profile | untested |
| 13 | Two players, same blocks | both hit one block: exactly one drop, one cash credit; both buy/sell at once; both ride the elevator | untested |
| 14 | Fresh Dig | temporarily set `Config.Shift.TriggerFraction = 0.01`; dig a few blocks; banner counts down, players in the mine are moved to camp, a resting artifact appears on Lost & Found, terrain is new, elevator still runs | untested |
| 15 | Performance | dig 20 min: watch Workspace instance count (`#Workspace:GetDescendants()`), MicroProfiler, Script Performance; `LocalFX` stays small | untested |
| 16 | Window sizes | 1920x1080, 1366x768, 1280x720, 1024x600, 800x600: shop, menu, journal fit; top HUD text does not overlap | untested |
| 17 | Signs/world | walk the camp: no floating signs, spawn-pad snag, sand in the pit, view from spawn/entrance/deep/elevator | untested |
