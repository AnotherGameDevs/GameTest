# Mine appearance, buried remnants and discovery pockets

Block-based excavation and every mining rule are unchanged. Code: `shared/MineStyle.luau` (pure rules),
`shared/MineDetailSpecs.luau` (remnant shapes), `server/Services/MineDetails.luau` (builds parts), `SiteService` (applies them).

## A. Variation inside layers (patches and bands, one material per layer)
| Layer | Material | Palette | Pattern |
|-------|----------|---------|---------|
| Soil | Ground | warm earth, darker/lighter loam | 3x2x3 **patches** (≈22% dark, 16% light) |
| Clay | Sandstone | terracotta family + pale lens | wavy 1-row **bands**, occasional lens |
| Stone | Slate | cool greys | patches + thin diagonal mineral **seams** (teal / quartz, ~3% of cells) |
| Ruins | Limestone | sandstone | alternating **courses**, weathered patches, rare carved blocks (~4%) |
Every value is a hash of (cell, layer, seed): no per-cell random noise, identical on every client, a new seed on each mine refresh.

## B. Buried remnants (appear only when a face is exposed)
Soil: roots, pebbles · Clay: pottery sherds · Stone: mineral seam, fossil impression · Ruins: worked-stone fragment, carved panel.
* Built **as children of the cell Part** on the first open face (neighbour dug, or the sky above the top row). When the cell is
  destroyed they vanish with it (the client also drops them instantly on a hit). A face that opens later builds its remnant then
  (`ExposeAround` → `ensureDetail`). Exit-shaft faces are never decorated.
* `CanCollide/CanTouch/CanQuery = false`, no shadows: they cannot block the dig ray, the crosshair or players. ≤ 12 parts per kind;
  at most `Config.Mine.MaxDetails = 220` live details; ambient chance 6–7% of exposed non-loot cells.
* **Reward tells are real:** a cell that really holds a coin / pottery shard / fossil fragment / ruin tablet shows that reward's own
  colours on its exposed face 45% of the time (90% inside pockets). Tells stand 0.25+ studs proud; ambient remnants are ≤ 0.16 studs,
  tone-on-tone and never use treasure colours. **Loot cells never get ambient remnants and non-loot cells never get tells**, so a
  remnant can neither hide nor fake a reward (tested). Nothing is built for hidden cells (parts exist only for exposed cells), so
  nothing shows through walls. Remnants have no prompts and no interaction.

## C. Discovery pockets (compact, seeded, regenerated with the mine)
* **Pottery cache** (Clay): 6 cells, tinted dark terracotta; a clay figurine + 2 pottery shards inside.
* **Fossil patch** (Stone): 3x1x3 pale-rock slab; 2 fossil fragments.
* **Broken masonry** (Ruins): 2x2x2 worked-stone cube; 1 ruin tablet.
Counts 3 / 3 / 2 per generation (`Config.Mine.Pockets`). Pocket loot replaces the rolled loot for those cells only. They sit in the
layer they belong to (so they are only reachable with the matching tool tier), stay ≥ 1 cell inside the grid edge (never touch the
elevator shaft wall), cannot overlap, and move on every refresh. Regeneration clears all tables first, so discoveries are never duplicated.

## Verified offline (`tests/mine_style_test.luau`, 269 checks)
determinism; palette size; patch coherence; seam/carved rates; ambient-vs-tell rules; remnant geometry (embedded, on the face, height
limits, no reward colours); pockets (counts, bounds, layers, overlap, loot ids, determinism, moves with seed).
Also: `docs/images/mine_strata_preview.png` is rendered from this same data (a data preview, not an engine screenshot).
## Not verified (needs Studio)
how it looks lit underground, performance with many exposed faces, readability of tells, `Enum.Material.Limestone` look.
