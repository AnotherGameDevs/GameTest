# Equipment effects

Status: **implemented and unit-checked offline; NOT yet seen in Roblox Studio.** Every row in the Studio checklist below is `not run`.

## What already existed (reused, not replaced)
`EffectsController` already owned all mining feedback: pooled debris chunks, block shake, cracks, camera kick (respects *Camera shake* in Settings),
the treasure reveal, and the dynamite blast. Sound goes through `AudioController` (respects *Master volume*, per-sound minimum gaps, 10-voice cap).
One effect pipeline was kept; it was made **tool-aware** instead of adding a second system:

| Piece | Role |
|---|---|
| `shared/ToolFx.luau` | Pure data: one profile per tool in `Defs.Tools`, caps, gates, trail geometry, strike window. No stats. |
| `client/Controllers/ToolFxController.luau` | Draws the profile: trail on the tool, puff, chips, sparks, ring, streak, break burst, sounds. |
| `client/Controllers/EffectsController.luau` | Unchanged owner of chunks / shake / cracks / camera; now asks `ToolFxController` for the per-tool part. Falls back to the old plain dirt feedback if it is missing. |
| `DigService` | The dig result broadcast now also names the digger's tool id (cosmetic profile choice only). |

## Mapping (seven tools, tier order; change a key in `ToolFx.Profiles` to re-assign)
| Tool | Profile | Swing | Impact | Break |
|---|---|---|---|---|
| Rusty Shovel (T1) | Starter | none | small earthy puff, 3 chips, dry low sound | 8 chips, dry |
| Digging Shovel (T2) | Improved hand | short pale blade trail (strike only) | sharper (higher) sound, 4 chips | 10 chips |
| Heavy Shovel (T3) | Reinforced | none | heavier (lower, louder) sound, 5 chips, broader cone | 14 chips, broad |
| Power Shovel (T4) | Professional | thin teal trail | teal cutting streak (beside the aim point), 4 chips | 12 chips |
| Jackhammer (T5) | Heavy excavation | none | brief ground-level ring, chunkier debris | chunky 15, ring |
| Drill (T6) | Industrial | none | amber sparks **on stone/ruins only**, mechanical tick | 11 chips, sparks on stone |
| Industrial Drill (T7) | Best tool | teal trail | teal ring + brass sparks (stone) + brass streak | short clean burst + teal/brass accent |

Judgement call to confirm: you listed *multi-block feedback* under "Industrial". The drill (T6) has no splash in the catalogue; the two tools with
splash are the Power Shovel (T4) and Industrial Drill (T7). So area feedback is **data-driven for every tool**: each extra cell the server reports
as hit gets a small chip burst (capped at 4 cells), and a tool with no splash never shows any. Nothing about mining stats was changed
(`tool_fx_test` pins power/rate/reach for all seven).

## Rules the code follows
* **Authoritative vs local.** The swing trail, chips, puff, sound and ring/streak happen immediately on the local swing (prediction). Cracks, **breaks**, area cells and other players' effects come from the server's `DigResult`.
* **Never loot-dependent.** Effects take the tool id, the layer (from cell depth), positions and the cells the server says were hit. No effect function receives or reads a block's reward, rarity or loot data. `tools/preflight.py` fails the build if `ToolFx`, `ToolFxController` or the dig-result path mention loot/rarity/treasure.
* **Soil makes dirt, stone makes sparks.** Sparks only fire when the layer is Stone or Ruins (`ToolFx.SparksOn`).
* **No flooding.** Each effect kind has a minimum gap (never under 0.08 s); live caps: 140 chunks, 22 sparks, 2 rings, 2 streaks, 1 trail per tool, no lights, no screen flashes. `tool_fx_test` simulates 10 s of continuous mining for all seven tools and checks the per-second counts and worst-case live debris.
* **Trails only during the strike.** The trail is created disabled on the tool's own `Handle` from the same part spec as the held tool/viewmodel (`ToolFx.RigPoints`), enabled for the 28%–54% window of the swing (max 0.2 s), then disabled by timer, with a heartbeat watchdog as a second guarantee.
* **Third person.** Other players within 90 studs get a restrained version: a short trail (max one per 0.25 s per player), half-size chips, quiet sound, no rings/streaks.
* **Cleanup.** `StopOwn()` (trails off, rings/streaks destroyed, puff cleared) runs on: menu/free-cursor, Roblox menu, window focus loss, carrying, tool change, any tool leaving the character (unequip / replace / stow). `StopAll()` (also removes airborne debris/sparks) runs on death, respawn, character removal and a new mine generation.
* **Settings.** Camera kick is skipped when *Camera shake* is off; all sounds scale with *Master volume*.
* **Crosshair.** Effects spawn on the mining face. The streak is offset ~1 stud from the aim point and lasts 0.14 s; the first-person trail rides the existing viewmodel, which already never crosses the crosshair.

## New sound slot
`Tick` (mechanical accent for drills) was added to `AudioController.Sounds`, using the same placeholder id as the UI click. Listed in `docs/AUDIO_MANIFEST.md`.

## Studio checks (all `not run`)
1. Each tool, mining Soil then Stone: swing trail only for T2/T4/T7, only during the strike, gone after release.
2. Impact / break differences are audible and visible as in the table; sparks only on stone/ruins.
3. Hold-mine with Jackhammer, Drill, Industrial Drill for 15 s: readable face, crosshair visible, no cloud or flash, frame rate steady.
4. Power Shovel / Industrial Drill: extra chips appear exactly on the neighbouring cells that crack/break.
5. Switch tools (shop, dev panel), open a menu mid-swing, carry an artifact, die, respawn: no trail or ring stays.
6. A second player mining 30–60 studs away shows a restrained trail/chips; at 100+ studs nothing.
7. Camera shake off / volume 0 respected.
8. Dig blocks that do and do not contain rewards: identical effects (compare recordings).
9. The smoke-puff texture (`rbxasset://textures/particles/smoke_main.dds`) renders; if not, tell me and I will swap it.
