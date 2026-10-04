# Tool tiers: stats, pricing rationale, evidence

**Status: PROVISIONAL.** Nothing here has been playtested. Every number below comes from `tools/economy_sim.py`
(an analytic model, not a recording of play). The server prints real measurements to the Output window every
`Config.Metrics.PrintInterval` seconds (`[Metrics] ... blocks/min ... cash/min`); replace these estimates with those.

## The eight tiers

Each tier changes about one thing versus the tier before it (damage, speed, reach, or area), never all four. Only tiers 4 and
7 are multi-block, both capped at **2 extra blocks per swing at 40% damage**. Tiers also **unlock layers** (see MINE_SHIFT.md).

| # | Name | Family | Power | Swings/s | Reach | Area | Price | Unlocks / changes |
|---|------|--------|------:|---------:|------:|------|------:|--------------|
| 1 | Rusty Shovel | Hand | 8 | 2.0 | 8 | single | free | Soil, Clay |
| 2 | Digging Shovel | Hand | 12 | 2.2 | 8 | single | $300 | faster and stronger |
| 3 | Heavy Shovel | Hand | 36 | 1.5 | 8 | single | $1,100 | **Stone layer**; soft blocks break in 1-2 hits |
| 4 | Power Shovel | Excavation | 36 | 1.5 | 8 | +2 blocks @40% | $5,500 | first area tier |
| 5 | Jackhammer | Excavation | 22 | 4.5 | 8 | single | $11,000 | **Ruins layer**; rapid fire |
| 6 | Drill | Excavation | 22 | 5.5 | 11 | single | $30,000 | faster, reaches deeper (11) |
| 7 | Industrial Drill | Industrial | 22 | 5.5 | 11 | +2 blocks @40% | $52,000 | area on top of tier 6 |
| 8 | Dynamite | Industrial | - | - | - | up to 14 blocks, once | $1,200 each | throwable, max carry 3, respects layer gating |

Backpacks (capacity sized to the dig rate of the tools a player owns when they can afford them):
Pouch 12 (free) · Big Satchel 30 ($120) · Field Pack 55 ($2,500) · Mining Pack 90 ($14,000) · Expedition Pack 140 ($40,000).
A smaller pack bought later never replaces a bigger one in use.

Layer HP: Soil 24, Clay 42, Stone 72, Ruins 110. Swings to break one block:

| Tool | Soil | Clay | Stone | Ruins |
|------|-----:|-----:|------:|------:|
| Rusty | 3 | 6 | locked | locked |
| Digging | 2 | 4 | locked | locked |
| Heavy / Power | 1 | 2 | 2 | locked |
| Jackhammer / Drill / Industrial | 2 | 2 | 4 | 5 |

## How prices were chosen (analytic model — NOT measured play)

`python3 tools/economy_sim.py` (mirrors Defs/Config; keep in sync by hand). Policy per tool = a sensible player digs the two
deepest layers that tool can break (40/60). Result with the shipped prices and packs:

| Tool owned | blocks/min | items/min | cash/min | minutes of mining to afford the next tool |
|------------|-----------:|----------:|---------:|----------:|
| 1 Rusty (pouch 12) | 16.2 | 3.8 | 107 | 2.8 -> Digging $300 |
| 2 Digging (satchel 30) | 26.8 | 6.3 | 185 | 5.9 -> Heavy $1,100 |
| 3 Heavy (30) | 29.3 | 8.3 | 949 | 5.8 -> Power $5,500 |
| 4 Power (field 55) | 46.8 | 13.3 | 1,542 | 7.1 -> Jackhammer $11,000 |
| 5 Jackhammer (55) | 38.2 | 11.4 | 3,799 | 7.9 -> Drill $30,000 |
| 6 Drill (mining 90) | 50.4 | 15.1 | 5,108 | 10.2 -> Industrial $52,000 |
| 7 Industrial (expedition 140) | 80.6 | 24.2 | 8,155 | end of ladder |

* First upgrade ~3 minutes away; later tiers 6-10 minutes each (targets, not measurements).
* Income steps up when a tool unlocks a richer layer (Heavy: x5, Jackhammer: x2.5). That jump is intended (the unlock IS the
  reward) and is why the *next* price rises steeply there, so no single purchase makes the remaining ladder instant.
* A full 2,880-block layer takes 36-177 minutes of continuous digging depending on tool, so layers do not run out quickly;
  the mine refresh (MINE_SHIFT.md) refills it when they do.
* **Previous "dive straight to the ruins" problem is closed by layer gating**, not by flattening loot.
* Tool prices in the old tables ($1,500 / $2,800 / $5,000 / $7,500 / $11,500) and the 14-row mine are superseded.

**What still needs real data:** the server prints `[Metrics]` blocks/min and cash/min (Studio sessions) - replace the model
with those after a recorded session. Until then every price is provisional.

## Save migration
v1 -> v2 (tools): unchanged (legacy `digging_shovel` owners keep it and are granted `heavy_shovel`).
v2 -> v3 (collection/hints): adds `Display` and `Guide`; experienced players skip the early hints. Owned tools keep their ids;
prices changed but nobody is charged retroactively. Unit-tested in `tests/migration_test.luau`.
