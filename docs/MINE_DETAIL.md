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
* Built **as children of the cell Part** on the first open face (neighbour dug, or the sky above the top row). When the cell is
  destroyed they vanish with it (the client also drops them instantly on a hit). A face that opens later builds its remnant then
  (`ExposeAround` → `ensureDetail`). Exit-shaft faces are never decorated.
* `CanCollide/CanTouch/CanQuery = false`, no shadows: they cannot block the dig ray, the crosshair or players. ≤ 12 parts per kind;
  at most `Config.Mine.MaxDetails = 220` live details; ambient chance 6–7% of exposed non-loot cells.
* **No reward tells (changed).** Intact cells never show a recognisable artifact, rarity colour, label or prompt — including naturally exposed
  top-layer cells. Ambient remnants are plain geology only (Soil: roots, pebbles · Clay: cracks, pebbles · Stone: seam, cracks · Ruins: rubble,
  mortar), placed independent of where loot is, so they neither hide nor indicate a reward. A reward is resolved by the server only when its block
  is destroyed. Remnants have no prompts and no interaction.

## C. Discovery pockets (hidden clustering only)
Pockets are now **invisible**: they only cluster hidden loot (no tint, no marker). The list below describes the hidden loot clusters.
* **Pottery cache** (Clay): 6 cells, a clay figurine + 2 pottery shards inside.
* **Fossil patch** (Stone): 3x1x3 pale-rock slab; 2 fossil fragments.
* **Broken masonry** (Ruins): 2x2x2 worked-stone cube; 1 ruin tablet.
Counts 3 / 3 / 2 per generation (`Config.Mine.Pockets`). Pocket loot replaces the rolled loot for those cells only. They sit in the
layer they belong to (so they are only reachable with the matching tool tier), stay ≥ 1 cell inside the grid edge (never touch the
elevator shaft wall), cannot overlap, and move on every refresh. Regeneration clears all tables first, so discoveries are never duplicated.

## Verified offline (`tests/mine_style_test.luau`, 269 checks)
determinism; palette size; patch coherence; seam/carved rates; no-reward-geometry rules; remnant geometry (embedded, on the face, height
limits, no reward colours); pockets (counts, bounds, layers, overlap, loot ids, determinism, moves with seed).
Also: `docs/images/mine_strata_preview.png` is rendered from this same data (a data preview, not an engine screenshot).
## Not verified (needs Studio)
how it looks lit underground, performance with many exposed faces, `Enum.Material.Limestone` look.
