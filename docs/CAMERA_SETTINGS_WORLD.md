# Shovel assembly, mouse-look, settings menu, and the rebuilt camp

**Nothing here has been run in Roblox Studio.** Offline checks that exist: Luau type-check (clean), and four pure-logic test
suites (`tests/run_all.sh`: 28 artifact, 14 migration, 16 settings, 118 tool-assembly checks). Everything on the playtest list at
the bottom is still unverified, and **no screenshots exist** (the environment this was written in cannot run Roblox).

## 1. Shovel assembly (root cause + fix)
* **Cause:** the held tool's `Handle` was built as a cylinder along X but the welds of every other part assumed it was
  already rotated to run along Y (the rotation lived in its `Offset`, which the held-tool builder dropped for the root part).
  The shaft therefore lay horizontal while the blade/socket sat where a vertical shaft would have put them. The shop preview posed
  every part from its offset, so it looked right, which is why only the held tool broke. The Drill's grip was also genuinely
  detached from its body (found by the new test).
* **Fix:** one documented tool axis (see `docs/ART_STANDARD.md`); root `Handle` is an invisible 0.4 cube at the origin; the
  shaft is an ordinary welded part; every tool part is non-colliding and not raycast.
* **First person:** a separate viewmodel built from the SAME part list (`ModelKit.BuildWelded`), posed with one
  `PivotTo(camera * swing * rest)` per frame (`ViewmodelMath` + `ViewmodelController`). The real tool is hidden locally while it
  is shown. The old per-part resize/fade hack is gone.
* **Proof offline:** `tests/tool_assembly_test.luau` runs the real specs and viewmodel maths: every tool is one connected
  assembly, the shaft is vertical, enters its socket, grip at -Y and working end at +Y, overall length <= 8 studs, the
  crosshair zone (60 px radius) stays empty at rest and through the whole swing at 16:9, 21:9 and 4:3, the tool sits in the
  lower right, and carried artifacts leave the view clear.

## 2. Mouse-look
* **Inspection:** the project had no custom camera code; mouse-look was Roblox's built-in camera (first person via
  `LockFirstPerson`). There were no duplicate multipliers in our scripts. The built-in camera has no per-game sensitivity
  multiplier (the only control is the player's *global* Roblox setting, which a game must not overwrite), so first person now uses
  our own camera (`CameraController`).
* **Formula (applied once):** `radians = mouseDeltaPixels x BASE x RobloxSensitivity x Setting`.
  `GetMouseDelta()` is pixels since the last frame, so the angle depends only on distance moved, not frame rate (no dt, smoothing,
  acceleration or inertia). Camera shake is `Humanoid.CameraOffset`, independent of look.
* **BASE = 0.25 deg/pixel is an estimate, not a measurement** of Roblox's built-in feel. Default setting 0.30 therefore gives ~0.075 deg/px
  (~120 deg per 5 cm at 800 DPI). Treat it as provisional; tune `BASE_DEGREES_PER_PIXEL` / the default after playtesting.
  The effective speed also follows the player's Roblox sensitivity.
* Third person (V) is Roblox's normal camera, unchanged.

## 3. Settings / menu
* Gear button (top right) or **P**. Escape is Roblox's own menu and is never overridden. Resume / Settings / Controls.
* Settings: mouse sensitivity (slider + numeric field, 0.05-2.00, step 0.01, reset), master volume, camera shake, invert vertical.
* Saved in `data.Settings` through the existing profile; the client sends the table, the server clamps/validates it
  (`SettingsSpec`, tested) and clamps again on load. They live outside the character, so they survive death and respawn.
* **Input modes:** `InputMode` is the single owner of cursor state (mining / Alt free-cursor / menu). Opening any menu releases the
  cursor, stops mouse-look, clears held mining and disables gameplay shortcuts; closing restores the previous mode (free-cursor
  stays free-cursor) and mining needs a fresh click. Nothing is paused on the server; carry state and teleport rules are untouched.
* Controls page reads the same `Bindings` table the controllers use.

## 4. World
* **Elevator (new, as requested):** a real moving elevator. Shaft outside the grid on the camp edge (now right of the pit, x 20..36).
  Right column: a physics car on a vertical `PrismaticConstraint` servo run by `ElevatorService`; five stops (surface, soil, clay,
  stone, ruins) aligned to the landings; call plates at every stop, ride prompts (up / down / surface) on the car; one queued
  request; watchdog reset. Usable while carrying an artifact. Left column: landings + the ladder kept as a fallback so nobody can be
  stranded. The grid face behind the car is closed by an iron plate; the landing half is exposed so players dig sideways into it.
  Above ground a timber/iron gantry stands on solid ground beside and in front of the mouth (never over the car or the grid).
* **Ground:** camp = compacted warm sand (floor top still y 0.5); routes = darker worn earth; excavation edge = gravel + disturbed soil.
  The cream rectangle and the gold spawn/sell platforms are gone (spawn pad is invisible; the sell area is a low tonal disc + dashed boundary).
* **Landscape:** large stepped sandstone mesas north and on both flanks, low dunes in the south corners, far mesas and a far ground plane
  beyond the unchanged +-170 boundary; the south-centre approach is left open; sparse scrub/rocks only at landform bases.
* **Stations rebuilt (new construction and silhouettes):** Equipment shop (timber frame, muted teal canopy, framed counter, rack of the
  real tool models), appraisal workstation (counter, balance scale, ledger, cream canopy, "SELL FINDS"), artifact receiving table (cream
  cloth, plaque, timber arch).
* **Clutter removed:** the old DIG HERE board (blocked the route), gold spawn pad, tall black sell pole and yellow disc, black shop backboard
  and red roof, the decorative rim posts. A tall entrance gate (12-stud-clear opening, lintel 8+ studs up) and a rope-and-post fence with gaps
  at the entrance and the elevator replace them. Route is >= 12 studs clear.
* **Idempotent:** `WorldBuilder.Build()` destroys and rebuilds `Workspace.World` (everything it creates is under it); lighting objects are
  found by name before creation.

## Still to verify in Studio (none of this has been seen)
1. Tool visuals: held (third person), first-person idle and swing, shop preview, equip/unequip, respawn, carrying an artifact, deposit.
   Roblox's default hold pose may point the tool differently than I assumed; if so the fix is `Tool.Grip`/`Rest()` constants.
2. Mouse feel at the default; whether `BASE` is in the right range; frame-rate independence (compare 30/60/144 FPS).
3. Menu: slider drag, numeric field, reset, persistence after rejoin (needs a published place), Alt/shop/menu cursor hand-offs,
   mining never starting from a click on UI.
4. Elevator: every stop, queued calls, riding with an artifact, car stuck/watchdog, passengers not sliding off or being squashed,
   `SetNetworkOwner` succeeding.
5. Camp: spawn view toward the mine, view back toward camp, wide landscape view, elevator entrance, nothing blocking the 10-stud route,
   fence gaps, signs not visible through walls.
6. Calling `WorldBuilder.Build()` twice leaves exactly one set of assets.
