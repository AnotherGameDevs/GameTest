# Relic PvP validation — run sheet for Studio (2+ players)

**Status of this sheet: tests 28–38 are NOT RUN.** This environment has no Roblox Studio, so I cannot execute them. Run them below and send me the
results (the table at the bottom, plus any Output errors / screenshots). Relic PvP stays **incomplete** until the full flow in section 2 passes.

## 0. Setup
1. Open `Build/DigAndRun.rbxlx` in Studio. **Test → Clients and Servers → 2 Players → Start.** (3 players for the third-player test.) No publishing needed;
   DataStore warnings are expected. Keep the **Server** window's Output open (View → Output → Server) for `[RelicService]` / errors.
2. Server command-bar helpers (type in the *server* view's command bar, not a client):
```lua
local S = game.ServerScriptService.Server.Services
local Relic, Cfg = require(S.RelicService), require(game.ReplicatedStorage.Shared.Config)
local function P(i) return game.Players:GetPlayers()[i] end
local function tp(i, x, y, z) P(i).Character:PivotTo(CFrame.new(x, y, z)) end
-- start a relic event 6 studs in front of player i (announcement, marker, HUD, physical relic after ~1.3 s)
local function spawnRelic(i) local h = P(i).Character.HumanoidRootPart; return Relic.Discover(P(i), "sun_mask", h.Position + h.CFrame.LookVector * 6) end
```
   Useful positions: spawn (0,3,98) · entrance gate (0,3,58) · recovery point (0,3,53) · SAFE-ZONE line z=64 · receiving table (24,3,73) · elevator mouth (28,3,58) ·
   mine surface (0,3,20). `Cfg.Relic.*` and `Cfg.Reset.*` can be changed live (server) for faster tests, e.g. `Cfg.Reset.IntervalMinutes = 0.5; Cfg.Reset.WarningSeconds = 20`.
3. **Do not change any balance value until you have the observed evidence in section 3.**

## 1. Tests 28–38 (what to do → what must happen)
| # | Do | Pass when |
|---|----|-----------|
| 28 | Dig toward the Ruins as P1 with `Cfg.Loot` unchanged, OR call `spawnRelic(1)` after breaking any block (Discover is the same code path LootService uses). Before the call walk around/dig: look for outlines/prompts/markers. | nothing about the relic is visible beforehand. On discovery BOTH players get the toast + red announcement naming the Sun Pharaoh Mask and P1, a gold "RELIC" marker, the HUD panel; after ~1.3 s the model with a "Take the relic (contested!)" prompt |
| 29 | P2 takes it (hold prompt). Then as P2: click on dirt, press G, press R / TO CAMP, try equipping the shovel (client: `game.ReplicatedStorage.Remotes.RequestEquip:FireServer("Tool","rusty_shovel")`), try a hand-fired `DigHit`. Walk, jump, ride the elevator, press X. | click/G/R/equip/DigHit all refused (nothing happens or a message); movement and elevator work; X places it; the relic is visibly held; HUD shows "YOU have it" + "DELIVER HERE" marker at the table |
| 30 | P1 (not carrying) stands 5 studs away: press F repeatedly. Then 12 studs away. Then put a dirt block / wall between. Then P2 presses F next to P1 who just attacked. | in range: control bar drops 25 per hit (1 hit/s max), burst + flash + small knockback, 4 hits drop it. Out of range / through a solid wall: nothing. Carrier F shoves P1 (not a bystander P3 who never attacked) |
| 31 | After the drop (4 hits) P1 takes it. Immediately P2 tries to hit/re-grab. | P1 gets full control; P2's hits within 3 s are ignored with the "protected" message and **do not spend P2's cooldown**; P2 can retake it later |
| 32 | P2 carries the relic into the elevator, P1 chases (rides the same car / waits at the exit). | carry state survives the ride; relic never rests on the car; nobody is trapped; record who wins the exchange and how long the trip took |
| 33 | Carry across z=64. Hit attempts inside. Wait in the safe zone without depositing. Then deposit another run. | PvP stops at the gold line. Nothing is awarded on entering. After ~20 cumulative seconds in the zone the relic returns to the entrance (recovery point) with the message. Deposit at the table pays $3,500 once, announces the depositor, adds the collection entry (journal), removes all indicators, shovel back |
| 34 | As carrier: (a) `P(2).Character.Humanoid.Health = 0`, (b) press the character-reset button, (c) leave the game (Test → stop a client). | each drops the relic at a recoverable spot outside camp (or the recovery point); never banked; not exclusive; the shovel returns after respawn |
| 35 | Try to place it with a wall between / on the elevator car / over the edge; also `Relic.Place` far outside the map via command bar is not possible. | refused with the message, or returned to the entrance |
| 36 | Both players hold the prompt on the same dropped relic at once; both press deposit when only one carries. | exactly one pickup winner; one payout only |
| 37 | `Cfg.Reset.IntervalMinutes = 0.2; Cfg.Reset.WarningSeconds = 15; Cfg.Relic... ` let a relic be carried when the countdown ends. | evacuation waits (banner "Reset waiting for the contested relic"), at most 90 s, then the relic expires with the announcement and no reward; nothing appears in camp; old prompts do nothing; a second `spawnRelic(1)` during Evacuating/Regenerating returns false |
| 38 | Normal mining with no event. | no F prompt/STRIKE button, mining/selling/personal artifacts as before |

## 2. The full event (priority)
Discover → carry → pursue → hit → drop → steal → elevator → enter camp → deposit, with 2 humans. Record every step and the time it took.

## 2b. Verify the recent fixes
* **Voluntary drop / re-pickup:** carrier presses X then immediately re-takes it → refused for 5 s ("You just dropped it..."), control/protection NOT restored. Repeat with a forced drop (knocked loose) and with a death.
* **Switching carrier / rapid ownership changes:** P1→P2→P1→P2 as fast as the rules allow: HUD/markers always show the single current carrier; one carry tool exists; no stuck state.
* **Pickup reach/visibility:** from 10–12 studs in the open it works; behind a wall (e.g. in the next tunnel) it is refused ("something in the way"); the prompt only shows within 10 studs.
* **Camp grace:** stand in the zone 10 s, step out 3 s, step back: the grace does not restart; place/re-pickup inside the zone is not possible (placing there is refused); after expiry the relic returns cleanly (model at the entrance boardwalk, marker moves, carrier gets the shovel back).
* **Reset vs relic:** a relic cannot be discovered while the mine is Evacuating/Regenerating; after a reset a fresh relic (new generation) can appear normally; no duplicate models in `Workspace.RelicEvent`.
* **Attack visibility:** solid cell/wall blocks; decorations (a tell/remnant, rope, lantern, the carrier's own tool) do not; a third player standing between attacker and carrier does NOT block (intentional: there is no body-block mechanic).
* **Remote spam:** on a client command bar run `for i=1,60 do game.ReplicatedStorage.Remotes.RelicAttack:FireServer() end` → at most one accepted attempt per 0.25 s (and 6 per 2 s); effects (burst/flash) appear only for APPLIED hits.

## 3. Gameplay questions to answer from play (evidence needed before any value changes)
* Can the carrier tell who is attacking (flash, burst, HUD, knockback direction)? Are successful hits obvious to both sides?
* Can attackers reasonably catch the carrier? (both walk 16 studs/s; attack range 7, cooldown 1 s, 4 hits to drop)
* Does the carrier get a fair chance to escape? Does the elevator create camping/trapping (single car, 14 studs/s, 1 s dwell, ladder beside it)?
* Is the 12-stud server reach believable (the prompt only appears within 10 studs)?
* Are the 5 s drop lockout and 20 s cumulative camp grace right for the real distances?
**Analytic expectations (NOT observations):** elevator mouth (z≈56) to the safe line (z=64) is 8 studs ≈ 0.5 s of walking, and the line to the receiving
table (z=73) is another ~0.6 s, so once a carrier surfaces they are almost untouchable; the real contest is underground and in the car (a 78-stud trip is ~6 s,
enough for 4 hits at 1 s cooldown if an attacker rides along). A 20 s grace is far longer than the walk to the table. These are hypotheses to check, not reasons to change values.

## 4. Results (fill in) — please send this table back
| # | Result (passed / failed / not run) | Observed problems | Notes |
|---|---|---|---|
| 28 | not run | | |
| 29 | not run | | |
| 30 | not run | | |
| 31 | not run | | |
| 32 | not run | | |
| 33 | not run | | |
| 34 | not run | | |
| 35 | not run | | |
| 36 | not run | | |
| 37 | not run | | |
| 38 | not run | | |
| Full event (§2) | not run | | |
| Fix checks (§2b) | not run | | |
