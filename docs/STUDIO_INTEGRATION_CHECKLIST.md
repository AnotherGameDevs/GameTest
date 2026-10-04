# Studio integration checklist (one prioritised list)

**File to open:** `Build/DigAndRun.rbxlx` (also delivered as `DigAndRun_build_20261004-1801-33f631b1.rbxlx`), branch `claude/amazing-albattani-9y7to1`.
Build id **20261004-1801-33f631b1** — must appear in Pause menu (P) as `Build:` and in server Output; size 583,095 bytes, SHA-256 `26c1516452774e95b6a874aa170dd45ac1775d4878eee8f557f6105c3da54f15` (see `Build/BUILD_INFO.txt`).
If the build id shown differs you opened an older file. After editing code run `bash tools/build.sh` (stamps a new id, tests, builds, verifies every script is in the file).
**Engine verification status: INCOMPLETE. Every row below is `not run` until you observe it.** Offline tests (`bash tests/run_all.sh`, `python3 tools/preflight.py`) do not count as engine checks.
Stop at the first failing step in a section, copy the Output errors and tell me which step.

## Setup used by every section
Test → Clients and Servers → 2 Players (1 for sections A–E). View → Output (Server + Client). For saving, follow `docs/SAVING_TEST.md` first (use a TEST place). Server command-bar helpers are in `docs/RELIC_PLAYTEST.md` §0.

## A. Game starts without errors  (priority 1 — stop here if it fails)
| Step | Expected | Result |
|---|---|---|
| A1 Open the file, press Play | No red errors in Server/Client Output. Server prints `[DIG & RUN!] Server ready.`; yellow warnings only about DataStore (unpublished place) | not run |
| A2 Spawn | Standing on the camp floor facing the mine; HUD top-left (cash/backpack), top-right (depth, gear, JOURNAL, MINE n% DUG … RESET IN m:ss), tutorial card "DIG" bottom-centre **with text** | not run |
| A3 No empty yellow outline | Press P, J, open/close shop, finish/skip tutorial: no empty rounded yellow frame remains anywhere | not run |
| A4 Camp walk | Walk spawn → gate (~40 studs). Shop (teal canopy), appraisal stall, receiving table, recovery pad "ARTIFACT RECOVERY" by the gate, gold SAFE ZONE stripe + 2 signs, elevator tower right of the pit, shelf at the west. No floating signs, no sand inside the pit, nothing blocking the route | not run |
| A5 Output check | no `WorldAudit` offender lines; `[DataService]` line states the save mode | not run |

### A2. Fixes under observation (priority 1b — all `not run`)
* **Untouched dirt shows no artifact:** walk the whole mine at spawn, look at every exposed top-layer face and walls of the entrance cut; nothing recognisable as an artifact/coin/shard anywhere until a block is dug. Repeat after a mine reset and when joining a running server.
* **SET COMPLETE banner:** complete a collection set; text fully visible at 1920×1080, 1366×768 and a small window (resize the Game window); centered, not over the crosshair, disappears after ~4 s, two completions queue; does not repeat on rejoin.
* **Save notice:** with an unpublished/API-off session the HUD shows "Test session — progress will not save"; in the isolated test experience it does not. Then run the rejoin test in `docs/ISOLATED_TEST_EXPERIENCE.md`.

### A3. Equipment effects and developer mode (priority 1c — all `not run`)
Use the DEV panel (`\` or the amber DEV button; Studio only) to unlock everything, then run the Studio checks in **`docs/EFFECTS.md`** (7 tools) and **`docs/DEVELOPER_MODE.md`** (panel, isolation, relic helper, reset helper).

## B. Fresh player: mine, sell, purchase, rejoin
| Step | Expected | Result |
|---|---|---|
| B1 Mine | Hold left click on dirt: block highlight = block hit; crack/shake, drops; "TOO FAR" label when out of reach; stone with Rusty shows "TOO HARD - needs the Heavy Shovel" | not run |
| B2 Backpack | Items fill 12 slots; "BACKPACK FULL" at 12; tutorial advances (mine → backpack → sell) | not run |
| B3 Sell | Walk into the gold disc: auto-sell popup, cash rises; backpack empties | not run |
| B4 Buy/equip | At the shop: preview rotates the real tool, comparison bars, Digging Shovel $300 (earn first), equip; mining visibly faster; Utility/Cosmetics tabs do not exist | not run |
| B5 Settings | P → sensitivity slider/number, volume, shake; Resume. Alt toggles free cursor; no stuck mining after menus/alt-tab/respawn | not run |
| B6 Rejoin | Stop and Play again (test store, `docs/SAVING_TEST.md`): cash, tools, equipped, settings, collection, tutorial progress restored; completed tutorial steps do not replay | not run |

## C. Hidden loot and complete mine reset
| Step | Expected | Result |
|---|---|---|
| C1 Concealment | Nothing about unexposed rewards shows (no outlines/prompts/names). Exposed faces may show a small part of the real item (coin/pottery/fossil/etc.); digging that block yields exactly that item | not run |
| C2 Layers | Soil→Clay→Stone→Ruins look different (patches/bands/seams/courses); remnants only on exposed faces and vanish with the block | not run |
| C3 Randomness | Note a few tell/pocket positions; `Cfg.Reset.IntervalMinutes = 0.5; Cfg.Reset.WarningSeconds = 20` (server bar) and wait: positions differ after the reset | not run |
| C4 Warning | Banner "MINE RESETS IN n s - leave by the ELEVATOR", status panel counts down, red banner + tick sound in the last 10 s; a second player joining mid-countdown sees the right time | not run |
| C5 Evacuation | At the deadline mining/pickup stop; players inside the mine are moved beside the recovery pad; messages say nothing was sold/deposited | not run |
| C6 Regeneration | New terrain, `DigSite.Generation` increments, elevator car at the surface and working, no leftover effects, hold-click through the reset hits nothing | not run |

## D. Artifact pickup, carrying, deposit, collection (personal artifacts)
| Step | Expected | Result |
|---|---|---|
| D1 Discover | Dig an Epic (Fossil Claw / Golden Scarab; use Ruins with a Jackhammer, or `LootService.Award` via command bar): reveal plays, then the physical artifact + "Pick up artifact" prompt appears | not run |
| D2 Carry | Pick up: shovel stowed, artifact held; click/G/R/equip refused with explanation; X places it; re-pick works; only the discoverer can pick it up | not run |
| D3 Deposit | At the receiving table: payout once, popup "ARTIFACT SECURED", collection entry unlocks only now; depositing twice is impossible | not run |
| D4 Journal/shelf | J: entry shows model, rarity, layer, count; "PUT ON SHELF" → west shelf shows it with a name plate and the heading "<your name>'s Collection" | not run |
| D5 Reset recovery | Carry one (or place one) inside the mine, force a reset (C3): it appears in ARTIFACT RECOVERY, owner-only pickup, nothing auto-deposited; deliver it normally | not run |

## E. Elevator
| Step | Expected | Result |
|---|---|---|
| E1 Call/ride | Prompts at each landing (SURFACE, SOIL, CLAY, STONE, RUINS); car travels (14 studs/s, ~6 s full depth), stops, nobody falls off or is crushed; carrying an artifact is allowed | not run |
| E2 Ladder | Ladder beside it works as the fallback exit | not run |
| E3 After reset | Car at the surface, working, no stuck prompts | not run |

## F. Two-player relic event  → run **`docs/RELIC_PLAYTEST.md`** in full (tests 28–38, the full event, fix checks, gameplay questions). Relic PvP remains **awaiting multiplayer validation**; record results in its table.

## G. Mesh and audio presentation
| Step | Expected | Result |
|---|---|---|
| G1 Primitive models (current) | Reveal / carried (1st+3rd person) / journal / shelf show the same model per artifact; ring opening visible, necklace on its stand, long names fit the plates; seven artifacts are the known-unfinished fallback | not run |
| G2 Mesh import (only after you follow `docs/ARTIFACT_MESHES.md`) | for each imported artifact: groups line up, scale matches, all five views use the mesh, buried tell protrudes 0.7 studs | not run (0 of 7 imported) |
| G3 Audio (current placeholders) | hit/break/reveal ladder/sell/buy/deposit/set-complete/error/UI/countdown tick are audible and distinguishable; master volume setting scales them; no stacking storm while digging | not run |
| G4 Audio replacement (only after `docs/AUDIO_MANIFEST.md`) | every cue plays the new asset; no 403/"failed to load" warnings in Output | not run (0 of 10 replaced) |

## Report back
Copy this file with the Result column filled (passed / failed / not run), add Output errors and screenshots/recordings. Failed or surprising items become the next fixes; nothing is marked engine-verified until you confirm it.
