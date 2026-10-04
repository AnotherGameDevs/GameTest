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
| 18 | Tutorial panel | fresh profile: hint card appears with text; when nothing is active NO outline anywhere (normal play, journal open, shop open, settings open); Skip tutorial (card button via Alt, and Settings) clears it for good; Restart tutorial (Settings) starts from "DIG"; die/respawn/rejoin: finished steps do not return | untested |
| 19 | Mine variation | descend: soil/clay/stone/ruins look different (patches/bands/seams/courses); remnants appear only on exposed faces and vanish with their block; pottery cache (clay), fossil patch (stone), broken masonry (ruins) exist and can be dug out; remnants never block the crosshair/mining | untested |
| 20 | Reward tells | a block showing a coin/pottery/fossil/tablet tell actually drops that item; ambient remnants (grey/low) never drop anything | untested |
| 21 | Fresh Dig + details | after a refresh: new arrangement, no leftover remnants, no duplicate pockets, instance count back to baseline | untested |
| 22 | Artifact models | reveal, carry (3rd/1st person), world pickup, journal icon and shelf all show the new models; ring opening visible; necklace on stand; names fit on plates; shelf heading says "<name>'s Collection" | untested |
| 23 | Buried tells | dig down: the real artifact model sticks out ~0.7 studs only on exposed faces; digging that block releases exactly that reward; unexposed rewards show nothing (no outline/prompt/name through walls) | untested |
| 24 | Fresh loot per generation | note the positions of a few tells/pockets, wait for a reset (or set `Config.Reset.IntervalMinutes = 1`): positions differ; rejoin mid-generation: board unchanged | untested |
| 25 | Reset with two players | A carries an artifact inside the mine, B has placed one down inside; 60 s warning shows on both (late joiner C sees the right countdown); at the deadline mining/pickup stop, both are moved out, both artifacts appear in ARTIFACT RECOVERY, nothing sold/deposited; each owner can pick up ONLY their own and must carry it to the receiving table | untested |
| 26 | Post-reset state | elevator at the surface and working, new terrain, old requests ignored (hold click through the reset), no old reveal effects, instance count back to baseline | untested |
| 27 | Mesh artifacts | after importing the OBJs (docs/ARTIFACT_MESHES.md): reveal, carry (1st/3rd person), journal, shelf and buried tell for the seven mesh artifacts | not possible yet |
| 28 | Relic discovery | dig to the Ruins until the Sun Mask block breaks (or temporarily raise its chance): no tell/outline beforehand; on break: announcement with name+discoverer to BOTH players, relic marker, HUD panel | untested |
| 29 | Carrier restrictions (server) | carrier: click does nothing, G does nothing, R/To Camp refused, tool equip refused (try a hand-fired remote), can walk/jump/use the elevator/place it down; relic visibly held | untested |
| 30 | Attacks and shove | other player: F within 7 studs hits (meter drops 25), through a wall does not, out of range does not, cooldown 1 s; carrier F shoves an attacker (not an unrelated bystander); knockback bounded, nobody flung into the void | untested |
| 31 | Drop + transfer + protection | 4 hits drop it; B takes it (prompt), control restored, A cannot immediately re-hit B for 3 s; A can take it back later; same relic id/state throughout | untested |
| 32 | Elevator pursuit | carrier rides the elevator with B chasing; relic/carry state survives; no stuck car, nobody trapped | untested |
| 33 | Safe zone / deposit / stalling | PvP stops at the gold line; deposit at the table pays once and registers the collection entry for the depositor only; standing in camp without depositing returns it to the entrance after 20 s | untested |
| 34 | Death / reset character / disconnect | each drops the relic at a recoverable spot (never in camp, never banked/exclusive) and the shovel returns to the carrier | untested |
| 35 | Inaccessible placement | try to place it through a wall / on the elevator car / outside the map: refused or returned to the entrance point | untested |
| 36 | Simultaneous requests | two players press the pickup prompt together; two players press deposit (only the carrier can): exactly one winner / one payout | untested |
| 37 | Mine reset during an event | reset countdown ends while carried: reset waits up to 90 s, then relic expires with the announcement, no reward, nothing moved into camp; stale requests ignored | untested |
| 38 | Peaceful loop intact | with no relic event: mining, selling, personal artifacts unchanged; F key and STRIKE button absent | untested |

