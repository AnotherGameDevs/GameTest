#!/usr/bin/env python3
"""Provisional economy model for DIG & RUN tool tiers.  NOT a playtest - an analytic estimate used to pick
prices before real data exists.  Mirrors src/shared/Defs.luau + Config.luau (keep in sync by hand).
Usage: python3 tools/economy_sim.py
"""
import math

# --- mirrors of game data -------------------------------------------------------------------------------
LAYERS = {  # id: (HP per block, treasure chance)
    "Soil": (24, 0.20), "Clay": (42, 0.26), "Stone": (70, 0.30), "Ruins": (100, 0.34)}
TREASURE = {  # value, {layer: weight}
    "old_coin": (8, {"Soil": 10, "Clay": 6}),
    "pottery_shard": (12, {"Soil": 8, "Clay": 8}),
    "bronze_ring": (40, {"Soil": 2, "Clay": 6, "Stone": 3}),
    "clay_figurine": (65, {"Clay": 6, "Stone": 4}),
    "fossil_fragment": (85, {"Clay": 3, "Stone": 8}),
    "ancient_necklace": (240, {"Clay": 1, "Stone": 5, "Ruins": 4}),
    "cut_gemstone": (320, {"Stone": 4, "Ruins": 5}),
    "fossil_claw": (900, {"Stone": 1, "Ruins": 4}),
    "golden_scarab": (1400, {"Ruins": 3}),
}
# tool: (name, power, rate, reach, splash(extra, fraction))   -- mirrors Defs.Tools (tier 8 Dynamite is a consumable)
TOOLS = [
    ("1 Rusty Shovel",       8, 2.0,  8, None),
    ("2 Digging Shovel",    12, 2.2,  8, None),
    ("3 Heavy Shovel",      36, 1.5,  8, None),
    ("4 Power Shovel",      36, 1.5,  8, (2, 0.4)),
    ("5 Jackhammer",        22, 4.5,  8, None),
    ("6 Drill",             22, 5.5, 11, None),
    ("7 Industrial Drill",  22, 5.5, 11, (2, 0.4)),
]
EFFICIENCY = 0.65      # share of time actually hitting a valid block (aiming, walking, retargeting)
REACH_BONUS = {8: 1.0, 11: 1.08}   # longer reach = less repositioning
TRIP_OVERHEAD_S = 30   # TO CAMP + sell + shop + drop back into the shaft
POLICIES = {           # share of blocks mined per layer
    "shallow (soil/clay)":  {"Soil": .5, "Clay": .5},
    "ref (soil/clay/stone)": {"Soil": .25, "Clay": .5, "Stone": .25},   # the reference mix used to price tiers
    "mid (clay/stone)":     {"Clay": .4, "Stone": .6},
    "deep (stone/ruins)":   {"Stone": .4, "Ruins": .6},
}
# Time-to-afford targets (minutes of mining with the PREVIOUS tool at the reference mix) used to set prices.
TARGET_MINUTES = [None, 3, 4, 5, 6, 7, 9]

def item_ev(layer):
    tot = ev = 0
    for v, w in TREASURE.values():
        if layer in w:
            tot += w[layer]; ev += w[layer] * v
    return ev / tot

def block_time(tool, layer):
    _, p, r, reach, splash = tool
    hp = LAYERS[layer][0]
    t = math.ceil(hp / p) / r                  # seconds of swinging per block, no splash
    if splash:
        extra, frac = splash
        # neighbours soak `frac` of each swing too; ~75% of that damage ends up useful (the faces you mine next)
        useful = 1 + extra * frac * 0.75
        t /= useful
    return t

def stats(tool, policy, capacity):
    mix = POLICIES[policy]
    t_block = sum(share * block_time(tool, l) for l, share in mix.items())
    t_block /= EFFICIENCY * REACH_BONUS[tool[3]]
    blocks_min = 60 / t_block
    items_per_block = sum(share * LAYERS[l][1] for l, share in mix.items())
    cash_per_block = sum(share * LAYERS[l][1] * item_ev(l) for l, share in mix.items())
    items_min = blocks_min * items_per_block
    avg_item = cash_per_block / items_per_block
    fill_s = capacity / items_min * 60
    cycle = fill_s + TRIP_OVERHEAD_S
    cash_min = capacity * avg_item / cycle * 60
    return blocks_min, cash_min, fill_s

def price_report():
    print("\nPrice derivation (reference mix, 30-slot backpack):")
    for i in range(1, len(TOOLS)):
        pol = "shallow (soil/clay)" if i == 1 else "ref (soil/clay/stone)"
        _, c, _ = stats(TOOLS[i - 1], pol, 30)
        print(f"  {TOOLS[i][0]:20s} {TARGET_MINUTES[i]} min x ${c:6.0f}/min = ${TARGET_MINUTES[i] * c:8.0f}")
    print("\nWhole 8064-block mine, reference mix:")
    for t in TOOLS:
        b, _, _ = stats(t, "ref (soil/clay/stone)", 30)
        print(f"  {t[0]:20s} {b:6.1f} blocks/min  -> {8064 / b:5.0f} min of continuous digging")


if __name__ == "__main__":
    print("Item EV by layer:", {l: round(item_ev(l), 1) for l in LAYERS})
    print("Cash per block   :", {l: round(LAYERS[l][1] * item_ev(l), 2) for l in LAYERS})
    for cap in (12, 30):
        print(f"\n=== backpack capacity {cap} ===")
        for pol in POLICIES:
            print(f"-- policy {pol}")
            for t in TOOLS:
                b, c, f = stats(t, pol, cap)
                print(f"   {t[0]:20s} blocks/min {b:6.1f}  cash/min {c:7.0f}  fill {f:5.0f}s")
    price_report()
