# Mala Suerte — prototype v3: what was done, what's left

Install: replace your whole `mala-suerte` folder with the one in `mala-suerte-prototype-v3.zip`, then open `project.godot` in Godot 4.7.

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

## Test results

All of these passed, run on this code:

| Suite | Checks |
|---|---|
| Logic, all 4 modes | all pass |
| Mouse | 9 |
| Tools / dev menu | 17 |
| Script check | 29 |
| La Llorona behaviour (new) | 23 |
| Lechuza | 7 |
| Mano | 15 |
| Difficulty | all pass |
| Navigation paths to all 30 test spots | 60 |
| Multiplayer, two game instances | host 5 + client 9 |

- The new La Llorona behaviour suite covers both escapes. Hiding in an alley works, and walking away in the open doesn't. Escaping a charge by getting into the casa and crouching works.
- The multiplayer test includes a new check that the client's HUD shows La Llorona noticing them.
- **Soak:** over 3 short nights, a bot that never hides was hunted every night and caught twice.
- **Final compile check:** 0 script errors.

**Not finished:** the full "walk La Llorona to every spot" suite (`aisuite:llorona_nav`) was cut off when you asked me to stop. Earlier runs got 29 of 30 spots. The one miss was the door problem above, which the fast navigation check confirms is fixed.

**Note:** the shimmer test can read high when other heavy programs are running (frames get skipped). Run it on its own.

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
6. **Run the full creature-navigation suite once**:
   `godot --path . -- --autotest=aisuite:llorona_nav`
