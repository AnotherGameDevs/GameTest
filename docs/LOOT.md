# Buried loot: generation, anti-farming, presentation

## Generation (`LootPlan`, pure; `SiteService.Generate`)
* Rolled **once per mine generation, on the server**, from `Random.new(lootSeed)` where `lootSeed` is a **fresh random server-only
  integer** (`Random.new():NextInteger`). It is never the constant 1337, never derived from the cosmetic seed, and never sent to clients.
  The cosmetic seed (`Config.Site.Seed + generation * 7919`) only varies colours and remnants.
* Per cell: `TreasureChance` of its layer, then the layer's weighted table (`Defs.PickTreasure`).
* **Important artifacts** (RequiresCarry): only in eligible cells (inside the grid, not the outer ring, not the bottom row, >= 2 cells from
  the exit-shaft side) and at most `Config.Loot.ImportantLimits[id]` per generation (claw 4, scarab 2, mask 1). Survivors are a uniform random
  subset of all rolled candidates (no depth bias); the rest become ordinary finds of that layer.
* **Discovery pockets** (pottery cache / fossil patch / broken masonry; hidden, no visual marker) are placed at random from the same seed: no fixed coordinates.
* A rejoining player never touches any of this; only a completed reset calls `Generate`.

## Claims and anti-farming
* `LootBoard:Claim(cell, generation)` returns a reward once, only for the current generation; destroyed cells claim through it, so
  simultaneous hits cannot award twice. `DigHit` carries the generation; mismatches are ignored.
* Existing rate limits kept (`DigHit`, purchases...) and added `ArtifactPickup`. Resets are server-timed only (MINE_RESET.md); nothing a
  client sends can reset the mine, and a reset needs >= 10 active minutes (depletion) or 20 (schedule). Important artifacts are capped per generation.
* Ordinary rewards are untouched (~95% of buried rewards are ordinary; tool pricing re-simulated in TOOL_TIERS.md). Artifacts are now a
  capped windfall, so ordinary value per block in stone/ruins is what drives the economy.

## Presentation (no through-wall information)
* Cell parts (and therefore remnants) exist only for **exposed** cells; unexposed rewards have no instance, highlight, name or prompt, and
  no loot coordinates exist on any client.
* **Intact cells never show a reward:** no artifact model, rarity colour, label or prompt on any exposed face (tells were removed after being observed as visible on untouched dirt). Guarded by `tests/mine_style_test.luau` and a reward-render allowlist in `tools/preflight.py`.
* Destroying the block makes the server resolve the reward, which follows the existing flow (ordinary: backpack + reveal; important: server
  discovery -> physical artifact -> carry-home). Nothing is a free-standing surface decoration.
