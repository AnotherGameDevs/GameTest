# Mala Suerte — prototype v4: what was done, what's left

Install: replace your whole `mala-suerte` folder with the one in `mala-suerte-prototype-v4.zip`, then open `project.godot` in Godot 4.7.

v3 starts from your original v2 zip. The previous session ran out of usage halfway through copying files into your folder, so your folder may be half-updated. Replace the whole folder rather than merging.

All testing was done in Godot 4.7.1 on Linux with a virtual display. I have not played it on your Windows machine.

---

## 1. Floor flicker / shimmer — fixed

**Causes found:**
- **Vertex snapping (the PS1 "wobble").** It also snapped vertices that were behind the camera. On the huge one-piece ground, that error spread across the whole floor every frame.
- **Ground texture.** It had no mipmaps, so it sparkled in the distance.
- **Roads and water.** They sat 1–3 cm above the ground and z-fought with it.
- **Snap grid too coarse.** It moved in 2-pixel steps.

**Fixes:**
- Only vertices in front of the camera are snapped, on a 1-pixel grid.
- Big surfaces are split into roughly 3 m pieces.
- Distant textures are mipmapped.
- Roads and water get a small depth bias.

**Measured** (sparkling ground pixels during a slow strafe, default settings):

| Map | Before | After |
|---|---|---|
| Old map | 1.26% | 0.30% |
| New street | 0.86% | 0.39% |

The PS1 look is unchanged.

**Extra bug fixed:** turning *Vertex wobble* off in Settings made the whole world render black.

Files: `shaders/ps1.gdshader`, `world/palette.gd`, `world/map.gd` (`box()`), `game.gd` (snap resolution).

## 2. La Llorona — readable now

She was hard to read for three reasons:
- Her crying wasn't positional.
- It got quieter as she got closer.
- She charged automatically after 12 s whatever you did.

Each state now has one tell and one way out:

| State | What you notice | What to do |
|---|---|---|
| Wandering | Weeping you can locate by direction | Keep your distance |
| **Noticed you** | Weeping suddenly sounds far away and muffled, a whisper, she stops and turns to you. HUD: **SHE HAS NOTICED YOU** | Get out of her sight **and** keep quiet (crouch or stand still) for 3 s. A bar fills while you hide. |
| Stalking | Wet footsteps; she glides to where she last saw or heard you | Same as above. Walking away in the open does **not** lose her. |
| **Charging** | A scream; she glows. HUD: **SHE'S CHARGING** | Sprint round a corner, then crouch out of sight |
| Lost you | Weeping returns. HUD: **She lost you.** | — |

- **What makes her charge:** getting within about 4.5 m, staring at her for about 0.8 s, sprinting near her, or staying exposed too long.
- **Bestiario and README:** rewritten to match.
- **Other modes:**
  - The Procesión and the F1 "Summon" now go through the "noticed" tell.
  - Wrong offerings in Ofrenda and a wrong herb in Limpia still make her hunt you directly, as before.

Files: `creatures/llorona.gd`, `ui/hud.gd`, `ui/bestiary.gd`, `modes/procesion.gd`, `game.gd`.

## 3. The Ofrenda map — rebuilt as a compact, real-looking pueblo

- **Size:** about 60 m from the casa to the camposanto gate (was 112 m). The play area went from 180×215 m to 90×132 m.
- **Streets:** one main street with sidewalks, plus a cross street.
- **Houses:** painted plaster, wall to wall. Each has barred windows, an open metal door, a darker painted lower band, a flat roof with a low wall and some water tanks.
- **Behind the houses:** patios with walls, alleys and a back lane by the creek.
- **Buildings:** Tienda "Abarrotes Lupita", Casa vacía, Taller, Comisaría, the plaza with its kiosk and laurels, and the Capilla de San Isidro.
- **Edges:** the troje and chicken coop on the east, the arroyo on the west, the milpa to the south, and the panteón at the north end.
- **Street details:** utility poles, streetlights and two parked vehicles.
- **No Día de Muertos dressing** on the map itself, as you asked.
- **Unchanged:** the casa and its interior, so all four modes work as before.
- **Doors and gates widened to 2 m.** One house was unreachable for La Llorona because of navigation rounding; every spot is reachable now.

Files: `world/map.gd`, `ui/dev_menu.gd` (teleports now come from the map), `modes/limpia.gd`, `modes/procesion.gd`.


## v4 additions

### 4. Warnings for every creature (not just La Llorona)
- One warning line above the crosshair says which creature is after **you**, most urgent first:
  1. La Llorona noticed you / charging
  2. **LA LECHUZA IS DIVING AT YOU** ("get under a roof")
  3. **SOMETHING SCRATCHES UNDER THE FLOOR** ("keep moving")
  4. **A WHISTLE FROM THE ROOFTOPS** ("keep your eyes down")
- New setting, **Gameplay → Creature hints**: switches off the "what to do" line and keeps the warning itself.
- These are driven by synced creature state, so they work for clients in multiplayer too.

### 5. Horror UI pass (placeholder, no imported art)
- **Main menu:** the actual pueblo at night behind the menu, pixelated like the game, with fog and wind.
  - The camera drifts slowly down the main street, and one streetlight flickers.
  - Now and then a pale figure stands at the far end of the road, then is gone.
  - The papel picado is drained of colour and torn.
- **Typography:** a serif title face (Georgia/Times on Windows) for titles, the clock, warnings, notes and the end screen.
- **Buttons:** quiet text rows that light up candle-amber when hovered, instead of boxes.
- **Panels:** near-black with hairline borders. The selected mode card glows instead of turning solid orange.
- **Notes you read:** a scrap of old paper with ink text, slightly askew.
- **HUD:**
  - The objective is dimmer.
  - The stamina and flashlight bars are thin, and the stamina bar fades out when full.
  - The crosshair is a small dot.
  - Toasts are in serif with no smeary outline.
- **End screen:** a large "Mala suerte." or "Amaneció." headline over the stats.

### 6. Fixes found along the way
- La Llorona could start the night in a patio wash basin about 14 m from the spawn and notice you in the first second. She now starts at water at least 35 m from the players.
- Her warning no longer shows through the card-reveal screen.

## Test results (all run on this exact build, Godot 4.7.1)
| Suite | Result |
|---|---|
| Script compile check | 0 errors |
| Logic: all 4 modes | pass |
| Mouse input | 9/9 |
| Tools / dev menu | 17/17 |
| Creature warnings (new) | 6/6 |
| La Llorona behaviour (tells, hiding works, walking away doesn't, charge escape, stare, catch, hearing) | 23/23, twice in a row |
| La Llorona physically walks to all 30 spots on the map | 30/30 |
| Navigation path check, all spots from two far corners | 60/60 |
| Lechuza / Mano | 7/7, 15/15 |
| Soak: 3 short nights with a bot that never hides | hunted it 3/3 nights, caught it twice |
| Multiplayer: 2 game instances (lobby, sync, revive, Llorona warning on the client) | host 5/5, client 9/9 |
| Floor shimmer (run alone) | passes |

**Bugs found and fixed during testing:**
- **She stood still at a patio gate.** La Llorona could stand still for up to 25 s at a patio gate when her wander goal fell outside the map. Patio gates are now 2.6 m wide, patio wash basins are no longer her water spots, and wander goals are clamped onto walkable ground.
- **The navigation test was outdated.** It hadn't been updated for her new rules.

## What still needs doing

1. **Play it on your PC**:
   - Ofrenda and one other mode.
   - Check that the floor no longer flickers on your GPU.
   - Check that La Llorona feels fair: is 3 s of hiding right? Is 4.5 m charge range right?
2. **Tuning knobs** at the top of `creatures/llorona.gd`: `NOTICE_TIME`, `LOSE_TIME`, `QUIET_NOISE`, `CHARGE_DIST`, `STARE_LIMIT`.
3. **The HUD hint lines** for La Llorona are always on. You may want them only for the first few nights, or as a Settings option.
4. **Map polish** (real models later):
   - Several signs are small and blur under pixelation.
   - Streetlight heads read as floating white blocks.
   - The kiosk and chapel are basic boxes.
5. **Not touched this time:** La Lechuza and La Mano rules. The playtest log showed only La Llorona problems.
6. **New UI is placeholder.** The serif font comes from your system (Georgia on Windows). For a real release, pick and import a licensed font into the project.
