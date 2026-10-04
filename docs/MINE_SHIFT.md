# Mine depth, layer gating and the "Fresh Dig" refresh

## What was wrong
* The grid was 24 x 24 x 14 (8,064 blocks). The late tools clear it in under an hour; a shaft to the richest layer was
  ~40 blocks from the surface, so a starter shovel earned more per minute than the whole tool ladder was priced for
  (`tools/economy_sim.py`, "big open balance problem" in the old TOOL_TIERS).
* Nothing refilled the mine: an exhausted mine stayed empty for the rest of the server's life.

## Changes (smallest coherent set)
1. **Deeper mine:** 24 x 24 x **20** (11,520 blocks), four layers of five rows each (`Config.Site.Depth`, `Config.Layers`).
   Everything that depends on depth is derived from config: bedrock, ground opening, ladder/elevator height, and the
   elevator stops (`WorldElevator.StopTops` is built from `Config.Layers`).
2. **Layer toughness:** HP Soil 24 / Clay 42 / Stone 72 / Ruins 110.
3. **Layer gating** (`Config.Layers[].MinToolTier`, `Defs.LayerAllows`): Soil + Clay need tier 1, **Stone needs tier 3**
   (Heavy Shovel), **Ruins need tier 5** (Jackhammer). The server ignores swings at a layer the equipped tool cannot break
   (no cooldown used, throttled "Too hard! ... needs a Heavy Shovel or better" notice), splash skips such cells, and the
   dynamite blast skips them too (by the thrower's equipped tier). The client shows "TOO HARD - needs the <tool>" under the
   crosshair, the shop's swing table shows "locked" / "(new!)" per layer. So each tier has content that is new to it:
   | Tier | New content |
   |------|-------------|
   | 1-2 Rusty/Digging | Soil + Clay (coins, shards, rings, figurines) |
   | 3-4 Heavy/Power | **Stone** (fossils, necklaces, gemstones, first artifacts) |
   | 5-7 Jackhammer/Drill/Industrial | **Ruins** (tablets, gems, Epic claw/scarab, Legendary Sun Mask) |
4. **Layer-specific discoveries:** every layer has a home set (see COLLECTION.md). New finds: Ruin Tablet (Rare),
   Sun Pharaoh Mask (Legendary, carry-home), plus models for the claw, figurine, shard, fossil.

## Replenishment: "Fresh Dig" (`MineShiftService`, `Config.Shift`, `ShiftSpec`)
Approach chosen: **reset the shared mine in place** (re-run `SiteService.Generate` with a new seed). No new terrain system,
the block grid and its raycast targeting are untouched.

Trigger (checked every 5 s, `ShiftSpec.ShouldRefresh`, unit-tested): any of
* >= 55% of all blocks dug, or
* >= 70% of the Ruins layer dug (nothing left for the strongest tools), or
* the mine is >= 60 min old **and** >= 10% dug (so a barely-touched mine is never wiped).

Sequence:
1. **Warning:** a 45 s countdown banner to every player ("FRESH DIG IN 30s - leave the mine!").
2. **Carriers:** anyone *carrying an artifact while inside the mine volume* delays the refresh (banner: "waiting for artifact
   carriers"), up to 120 s. After that their artifact is dropped through the normal loss path.
3. **Artifacts are never deleted:** every *resting* artifact inside the mine is moved to the camp **Lost & Found** pad
   (`ArtifactService.RelocateFromMine`), stays claimed by its discoverer, and the owner is told. Carried artifacts held by
   players outside the mine (e.g. at camp) are unaffected.
4. **Players inside the mine volume** (grid footprint + exit shaft, below the rim) are moved to the camp spawn.
5. The grid is regenerated (new seed = `Seed + n * SeedStep`), a "THE MINE HAS BEEN REFRESHED!" banner appears.
6. **Elevator / ladder / camp are outside the grid** and are not touched; they keep working throughout.

Unsaved state: the refresh is server-session state. Players' cash, tools, collection are unaffected.

## Verified vs not
* Verified offline: decision rule (tests/collection_test.luau), gating data invariants, `ArtifactRecords.Relocate/Dropped`,
  type-check. Economy figures are from `tools/economy_sim.py` (analytic, **not a playtest**).
* **Not verified (needs Studio):** the refresh sequence in a live server, players being moved out, the banner, relocation
  of real models, physics of the elevator after a refresh. See `docs/PLAYTEST_PLAN.md`.
