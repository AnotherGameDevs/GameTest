# Camp spacing and the sand over the dig area

**Not run in Roblox Studio; no before/after screenshots exist** (no engine in this environment). Offline evidence: type-check clean and
the pure-logic suites pass (`tests/run_all.sh`: 70 ground-plan and 28 camp-layout checks are new this pass). The runtime `WorldAudit`
prints its result to the server Output on every world build, so the correction can be confirmed in play.

## The actual cause of the sand
Found by checking each suspect against the real geometry, not by changing materials:

| Suspect | Verdict |
|---|---|
| Ground slabs across the footprint | No. The slabs stop at the grid edge (and are now generated that way, see below). |
| Gravel / path overlays crossing into dig cells | No. Rim strips, patches, routes all start outside the grid. |
| Terrain in the mine space | No. The project uses no Terrain. |
| Dig-cell material | No. Cells are SmoothPlastic in the layer colours; nothing sand-coloured. |
| **A decorative far-ground sheet** | **YES: the cause.** |
| A camp piece over the shaft | Yes, a second (smaller) overlap. |

* **Primary cause:** in the last world pass I added `FarGround`, one 1400 x 2 x 1400 stud `Sand`-material part centred on the map with its
  top at y = -0.1. That placed it **inside the top two rows of dig cells** (cells occupy y 0 to -4). It is non-colliding, so while a top
  cell is intact you cannot see it, but the moment a cell was mined the pale rippled sand showed through the hole (flush with the surface,
  looking like a sand tile replacing the block) and hid the real cell below, while you could still fall through it. This is the
  cell-sized pale tile in your screenshot.
* **Secondary overlap:** `CampApron` (a Sand-material border pad) extended north to z = 53, across the elevator shaft's footprint and into
  the car's travel path at the surface stop.
* Nothing was hidden by transparency or by nudging a surface upward.

## The fix
* `Grid.Bounds()` is now the single definition of the mine volume. `GroundPlan.Subtract(outer, holes)` (pure, tested) tiles the playable
  square minus the holes (mine footprint + elevator shaft, both derived from `Config.Site` and `Config.Exit`). The ground slabs, camp
  apron and gravel rim are all built from it, so none of them can cross the excavation.
* `FarGround` is now a four-piece frame **outside** the playable square (distance > the map boundary), flush with the slab tops. It cannot
  reach the mine.
* `CampApron` is produced through the same hole subtraction and no longer extends north of the camp floor.
* `WorldAudit` runs at the end of `WorldBuilder.Build()` and reports any world part inside the mine volume (only `Bedrock` is allowed) or
  inside the shaft (only the `Elevator` folder is allowed), by path.
* Disturbed-soil patches, the fence and the boardwalk are positioned relative to `Grid.Bounds()` so they follow the configuration.

## Camp spacing (everything comes from `Config.Camp`)
Mine and elevator are unchanged. The camp floor now spans x -40..40, z 56..108 (it starts exactly at the shaft edge). The entrance gate is at z 58.5.

| Item | Position | Rule |
|---|---|---|
| Spawn / return-to-camp | (0, 98) | 39.5 studs straight along the route to the gate (target 35-45) |
| Arrival area | x +-8, z 90..106 | clear of every station, the sell disc and the lost & found pad |
| Appraisal stall (west) | (-18, 70), sell trigger centre (-18, 82) | |
| Shop (east) | (20, 88) | 22.8 studs of walking width from the appraisal stall (>= 12) |
| Receiving table | (24, 73) | ~19 studs from the elevator exit; >= 8 from the gantry |
| Sightline | x +-6 from spawn to the gate | nothing in it |
| Rim clearance | stations start >= 17 studs from the mine rim (>= 8) | |

Spawn, return-to-camp destination, shop prompt, sell trigger and deposit check all read these values (the models are built from the same
config), and the UI's "BASE CAMP" label and shop auto-close use them too. No props were added to the opened space.
`tests/camp_layout_test.luau` fails if any of these rules is broken.

## To verify in Studio (not yet done)
1. Spawn view toward the mine; mine view back to camp; wide landscape; elevator entrance; before/after shots.
2. Dig beside every edge of the mine and near the elevator (including the top row, where the sand used to show): no sand sheets, no
   flickering, no covering surfaces in the shafts. Read the `[WorldAudit]` line in the server Output (expect "OK ... none inside").
3. Return to camp lands at (0, 98); shop opens and buys; selling triggers in the (-18, 82) circle; deposit works at the new table.
4. Call `WorldBuilder.Build()` again (e.g. from the command bar) and confirm one set of assets and the audit still OK.
