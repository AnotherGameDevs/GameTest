# Tool tiers: stats, pricing rationale, evidence

**Status: PROVISIONAL.** Nothing here has been playtested. Every number below comes from `tools/economy_sim.py`
(an analytic model, not a recording of play). The server prints real measurements to the Output window every
`Config.Metrics.PrintInterval` seconds (`[Metrics] ... blocks/min ... cash/min`); replace these estimates with those.

## The eight tiers

Each tier changes about one thing versus the tier before it (damage, speed, reach, or area), never all four.
Only tiers 4 and 7 are multi-block, and both are capped at **2 extra blocks per swing at 40% damage**.

| # | Name | Family | Power | Swings/s | Reach | Area | Price | What changes |
|---|------|--------|------:|---------:|------:|------|------:|--------------|
| 1 | Rusty Shovel | Hand | 8 | 2.0 | 8 | single | free | baseline |
| 2 | Digging Shovel | Hand | 12 | 2.2 | 8 | single | $300 | faster and stronger |
| 3 | Heavy Shovel | Hand | 36 | 1.5 | 8 | single | $1,500 | fewer, bigger hits (soft blocks break in 1) |
| 4 | Power Shovel | Excavation | 36 | 1.5 | 8 | +2 blocks @40% | $2,800 | first area tier (the old "powerful shovel" idea, capped) |
| 5 | Jackhammer | Excavation | 22 | 4.5 | 8 | single | $5,000 | rapid-fire, light hits |
| 6 | Drill | Excavation | 22 | 5.5 | 11 | single | $7,500 | faster + reaches deeper |
| 7 | Industrial Drill | Industrial | 22 | 5.5 | 11 | +2 blocks @40% | $11,500 | area on top of tier 6 |
| 8 | Dynamite | Industrial | - | - | - | up to 14 blocks, once | $400 each | throwable, single use, max carry 3 |

Layer HP: Soil 24, Clay 42, Stone 70, Ruins 100. Swings to break one block:

| Tool | Soil | Clay | Stone | Ruins |
|------|-----:|-----:|------:|------:|
| Rusty | 3 | 6 | 9 | 13 |
| Digging | 2 | 4 | 6 | 9 |
| Heavy / Power | 1 | 2 | 2 | 3 |
| Jackhammer / Drill / Industrial | 2 | 2 | 4 | 5 |

The old Digging Shovel (Power 18, 3/s, 3x3x3 splash at 55%, $180) is retired; its behaviour became tier 4 with a
hard cap. Players who owned it are migrated (see below).

## How prices were chosen (model estimates)

Assumptions (all in `economy_sim.py`): 65% of time is spent actually swinging at valid blocks, trips cost 30 s of
overhead, a 30-slot backpack, and the existing loot tables/layer HP unchanged. "Reference mix" = 25% soil, 50% clay,
25% stone. Price = target minutes of mining with the previous tier x its cash/min.

| Tier owned | Blocks/min (ref) | vs previous | Cash/min (ref) | Target minutes to afford the next tier | Next tier price |
|------|-----------------:|------------:|---------------:|---------------------------:|------:|
| 1 Rusty | 13.0 | - | 240 (110 shallow) | 3 min | $300 |
| 2 Digging | 21.5 | x1.65 | 383 | 4 min | $1,500 |
| 3 Heavy | 33.4 | x1.56 | 570 | 5 min | $2,800 |
| 4 Power | 53.5 | x1.60 | 848 | 6 min | $5,000 |
| 5 Jackhammer | 70.2 | x1.31 | 1,052 | 7 min | $7,500 |
| 6 Drill | 92.7 | x1.32 | 1,294 | 9 min | $11,500 |
| 7 Industrial | 148.3 | x1.60 | 1,770 | - | - |

* **Starter feel:** the first upgrade is ~3 minutes away. One full 12-slot trip is ~$330 at shallow depth.
* **No single purchase trivialises the mine:** each tier is x1.3-1.65 in blocks/min. Clearing the whole 8,064-block mine
  takes 620 min (Rusty) down to 54 min (Industrial Drill) of continuous digging.
* **Sequential unlock:** a tier can only be bought after the previous one (`Config.Shop.SequentialTools`), so a windfall
  cannot skip the ladder.
* **Dynamite ($400, max 3):** a stick breaks up to 14 nearby blocks (~$270 of loot at the reference mix, much more in
  stone/ruins, subject to backpack space). It is a time saver, not a profit engine. It is single-use, so it is a
  recurring sink rather than a one-off purchase.

## The big open balance problem (needs a decision)

Depth, not tools, dominates income, and nothing stops a new player digging straight down:

| Tool | shallow | reference | **deep (stone/ruins)** |
|------|--------:|----------:|-----------------------:|
| Rusty | $110/min | $240/min | **$1,012/min** |
| Industrial Drill | $735/min | $1,770/min | **$8,613/min** |

A starter shovel in the ruins out-earns the whole ladder priced for the reference mix, and a shaft to the ruins is only
~40 blocks. So **a player who dives immediately can afford every tier within minutes**, which defeats the pricing above.
This comes from the unchanged loot tables (ruins ~$220 per block vs soil ~$2.6). Options, none applied yet:
1. Gate layers by tool (e.g. a minimum Power per layer, or "this block is too hard" below a tier).
2. Flatten the loot value gradient.
3. Scale the sell value of items by tool tier or depth progress.

## Save migration (v1 -> v2)

`DataMigrations.luau` (unit-tested, `tests/migration_test.luau`):
* `rusty_shovel` unchanged. Saves with the old `digging_shovel` **keep ownership of `digging_shovel`** (it is now the
  modest tier 2), are **granted `heavy_shovel`** (tier 3) as compensation for the stronger tool they paid for, and have
  their equipped tool set to the best tier owned. No refund, no further skipping. Logged in `MigrationLog.ToolsV2`.
* A repair pass removes unknown ids and fixes an equipped-but-unowned tool. Cash is never touched.
* Edit `LEGACY_TOOL_GRANTS` to change the policy.
