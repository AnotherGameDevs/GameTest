-- Run via tests/run_all.sh. Collection journal rules, display list, set completion, guide hints, mine-shift decision and
-- the layer-gating / progression data invariants.
local stubs = require("./_build/shared/__stubs")
local Config = require("./_build/shared/Config")
local Defs = require("./_build/shared/Defs")
local CollectionSpec = require("./_build/shared/CollectionSpec")
local GuideSpec = require("./_build/shared/GuideSpec")
local ShiftSpec = require("./_build/shared/ShiftSpec")
local TreasureModels = require("./_build/shared/TreasureModels")
local PackModels = require("./_build/shared/PackModels")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

-- ---------------------------------------------------------------- journal entries -----------------------------------
do
	local n = 0
	for _ in pairs(Defs.Treasure) do n += 1 end
	check("one journal entry per treasure type", #CollectionSpec.Entries == n)
	local sets = CollectionSpec.Sets({})
	local members = 0
	for _, s in ipairs(sets) do members += s.Total; check("set " .. s.LayerId .. " is not empty", s.Total > 0) end
	check("sets partition the entries", members == n)
	check("empty collection: nothing complete", not sets[1].Complete)
	for id, def in pairs(Defs.Treasure) do
		if def.RequiresCarry then
			check("important artifact has a polished model: " .. id, def.Model ~= nil and #TreasureModels.Specs(id, def) > 1)
		end
	end
end

-- ---------------------------------------------------------------- registering -------------------------------------
do
	local c = {}
	local isNew, done = CollectionSpec.Register(c, "old_coin", 100)
	check("first find is new", isNew and done == nil and c.old_coin.Count == 1 and c.old_coin.FirstFound == 100)
	isNew = CollectionSpec.Register(c, "old_coin", 200)
	check("duplicate is not new, counts up, keeps FirstFound", not isNew and c.old_coin.Count == 2 and c.old_coin.FirstFound == 100)
	check("unknown ids are ignored", CollectionSpec.Register(c, "nope", 1) == false and c.nope == nil)

	-- complete the Soil set: exactly one completion acknowledgement
	local soil
	for _, s in ipairs(CollectionSpec.Sets({})) do if s.LayerId == "Soil" then soil = s end end
	local completions = 0
	local c2 = {}
	for _, id in ipairs(soil.Members) do
		local _, comp = CollectionSpec.Register(c2, id, 1)
		if comp then completions += 1; check("completion names the layer", comp == "Soil") end
	end
	check("a set completes exactly once", completions == 1)
	local _, again = CollectionSpec.Register(c2, soil.Members[1], 2)
	check("re-registering a member never re-completes", again == nil)
	local found, total = CollectionSpec.Totals(c2)
	check("totals", found == soil.Total and total == #CollectionSpec.Entries)
end

-- ---------------------------------------------------------------- display list -------------------------------------
do
	local c = {}
	CollectionSpec.Register(c, "old_coin", 1)
	CollectionSpec.Register(c, "pottery_shard", 1)
	CollectionSpec.Register(c, "bronze_ring", 1)
	CollectionSpec.Register(c, "clay_figurine", 1)
	CollectionSpec.Register(c, "fossil_fragment", 1)
	local list, ok = CollectionSpec.ToggleDisplay({}, "old_coin", c)
	check("add a discovered artifact", ok and #list == 1 and list[1] == "old_coin")
	local _, ok2, why2 = CollectionSpec.ToggleDisplay(list, "golden_scarab", c)
	check("cannot display an undiscovered artifact", not ok2 and why2 == "NotDiscovered")
	local _, ok3, why3 = CollectionSpec.ToggleDisplay(list, "not_real", c)
	check("unknown id rejected", not ok3 and why3 == "Unknown")
	local _, ok4 = CollectionSpec.ToggleDisplay(list, 42, c)
	check("non-string rejected", not ok4)
	list = CollectionSpec.ToggleDisplay(list, "old_coin", c)
	check("toggling again removes it", #list == 0)
	for _, id in ipairs({ "old_coin", "pottery_shard", "bronze_ring", "clay_figurine" }) do list = CollectionSpec.ToggleDisplay(list, id, c) end
	check("shelf holds exactly DisplaySlots", #list == Config.Collection.DisplaySlots)
	local full, okFull, whyFull = CollectionSpec.ToggleDisplay(list, "fossil_fragment", c)
	check("full shelf refuses additions, never replaces", not okFull and whyFull == "Full" and #full == Config.Collection.DisplaySlots and full[1] == "old_coin")
	local dirty = CollectionSpec.SanitizeDisplay({ "old_coin", "old_coin", "golden_scarab", "zzz", "bronze_ring" }, c)
	check("sanitize drops duplicates, undiscovered and unknown ids", #dirty == 2 and dirty[1] == "old_coin" and dirty[2] == "bronze_ring")
	check("sanitize handles garbage", #CollectionSpec.SanitizeDisplay("x", c) == 0)
end

-- ---------------------------------------------------------------- guide ------------------------------------------
do
	local names = { Dig = "LEFT CLICK", Sell = "R", Place = "X", Journal = "J" }
	local function state(over)
		local s = { Cash = 0, Count = 0, Capacity = 12, Stats = { BlocksDug = 0, CashEarned = 0, DeepestDepth = 0 }, OwnedToolCount = 1,
			NextToolPrice = 300, NextToolName = "Digging Shovel", Carrying = false, HasDeposited = false, CollectionFound = 0, Touch = false, depthMeters = 0 }
		for k, v in pairs(over or {}) do s[k] = v end
		return s
	end
	check("fresh player: the mining hint", GuideSpec.Active(state(), {}) == "mine")
	check("mining hint names the real binding", select(2, GuideSpec.Text("mine", state(), names)):find("LEFT CLICK", 1, true) ~= nil)
	check("touch text differs", select(2, GuideSpec.Text("mine", state({ Touch = true }), names)):find("Tap", 1, true) ~= nil)
	check("mining hint ends after a few blocks", GuideSpec.Active(state({ Stats = { BlocksDug = 4, CashEarned = 0, DeepestDepth = 0 } }), {}) == nil)
	check("backpack hint once something is stored", GuideSpec.Active(state({ Count = 1, Stats = { BlocksDug = 6, CashEarned = 0, DeepestDepth = 0 } }), {}) == "backpack")
	check("sell hint after a few items", GuideSpec.Active(state({ Count = 4, Stats = { BlocksDug = 12, CashEarned = 0, DeepestDepth = 0 } }), { backpack = true }) == "sell")
	check("sell text names the teleport key", select(2, GuideSpec.Text("sell", state(), names)):find("R", 1, true) ~= nil)
	local afterSale = state({ Cash = 400, Stats = { BlocksDug = 30, CashEarned = 400, DeepestDepth = 0 } })
	check("upgrade hint when a sale makes the next tool affordable", GuideSpec.Active(afterSale, { mine = true, backpack = true, sell = true }) == "upgrade")
	check("upgrade hint ends once a second tool is owned", GuideSpec.Active(state({ Cash = 400, OwnedToolCount = 2, Stats = { BlocksDug = 30, CashEarned = 400, DeepestDepth = 0 } }), { mine = true }) ~= "upgrade")
	check("elevator hint appears at depth", GuideSpec.Active(state({ depthMeters = 12, Stats = { BlocksDug = 50, CashEarned = 500, DeepestDepth = 12 }, OwnedToolCount = 2 }), { mine = true, backpack = true, sell = true, upgrade = true }) == "elevator")
	check("artifact hint while carrying", GuideSpec.Active(state({ Carrying = true, Stats = { BlocksDug = 80, CashEarned = 900, DeepestDepth = 30 }, OwnedToolCount = 3 }), { mine = true, backpack = true, sell = true, upgrade = true, elevator = true }) == "artifact")
	check("artifact text explains the restrictions", select(2, GuideSpec.Text("artifact", state(), names)):find("dig", 1, true) ~= nil)
	check("collection hint after the first entry", GuideSpec.Active(state({ CollectionFound = 1, OwnedToolCount = 3, Stats = { BlocksDug = 80, CashEarned = 900, DeepestDepth = 10 } }), { mine = true, backpack = true, sell = true, upgrade = true, elevator = true, artifact = true }) == "collection")
	check("done hints never show again", GuideSpec.Active(state(), { mine = true }) == nil)
	check("valid ids", GuideSpec.IsValid("mine") and not GuideSpec.IsValid("hack") and not GuideSpec.IsValid(5))
	for _, id in ipairs(GuideSpec.Order) do
		local t, b = GuideSpec.Text(id, state(), names)
		check("hint text exists: " .. id, #t > 0 and #b > 0)
	end
end

-- ---------------------------------------------------------------- tutorial lifecycle ----------------------------------
do
	local function snap(over)
		local d = { Cash = 0, Count = 0, Capacity = 12, Stats = { BlocksDug = 0, CashEarned = 0, RelicsExtracted = 0, DeepestDepth = 0 },
			OwnedTools = { rusty_shovel = true }, Collection = {}, Carrying = nil }
		for k, v in pairs(over or {}) do d[k] = v end
		return d
	end
	local names = { Dig = "LEFT CLICK", Sell = "R", Place = "X", Journal = "J" }
	local function active(d, guide, base) return GuideSpec.Active(GuideSpec.StateFrom(d, base, { Touch = false, depthMeters = 0 }), guide) end

	-- fresh profile
	check("fresh profile: shows the mining hint", active(snap(), {}, {}) == "mine")
	-- partially completed (saved): never replays the finished steps
	local partial = { mine = true, backpack = true }
	local d = snap({ Count = 4, Stats = { BlocksDug = 20, CashEarned = 0, RelicsExtracted = 0, DeepestDepth = 0 } })
	check("partial: resumes at the next step (sell)", active(d, partial, {}) == "sell")
	check("partial: finished steps stay finished", GuideSpec.Active(GuideSpec.StateFrom(d, {}, { depthMeters = 0 }), { mine = true, backpack = true, sell = true }) == nil)
	-- completed profile: nothing shows, even after respawn/rejoin (same saved table)
	local all = {}
	for _, id in ipairs(GuideSpec.Order) do all[id] = true end
	check("completed: no guidance", active(snap({ Count = 3 }), all, {}) == nil)
	-- skip
	check("skip: no guidance even for a brand-new state", active(snap(), { skipped = true }, {}) == nil)
	check("skip: nothing newly satisfied is re-reported", #GuideSpec.NewlySatisfied(GuideSpec.StateFrom(snap(), {}, {}), { skipped = true }) == 0)
	-- restart: a veteran restarts, old lifetime progress does not count
	local veteran = snap({ Cash = 5000, Stats = { BlocksDug = 900, CashEarned = 20000, RelicsExtracted = 3, DeepestDepth = 40 },
		OwnedTools = { rusty_shovel = true, digging_shovel = true, heavy_shovel = true }, Collection = { old_coin = { Count = 1 } } })
	local base = GuideSpec.Baseline(veteran)
	check("baseline records lifetime counters", base.BlocksDug == 900 and base.CashEarned == 20000 and base.Tools == 3 and base.Found == 1)
	check("veteran WITHOUT a baseline would see everything done", #GuideSpec.NewlySatisfied(GuideSpec.StateFrom(veteran, {}, {}), {}) >= 3)
	check("restart: guidance starts from the mining hint again", active(veteran, {}, base) == "mine")
	check("restart: nothing is auto-completed from old stats", #GuideSpec.NewlySatisfied(GuideSpec.StateFrom(veteran, base, {}), {}) == 0)
	local progressed = snap({ Stats = { BlocksDug = 905, CashEarned = 20000, RelicsExtracted = 3, DeepestDepth = 40 },
		OwnedTools = veteran.OwnedTools, Collection = veteran.Collection, Cash = 5000 })
	check("restart: new digging completes the first step", table.find(GuideSpec.NewlySatisfied(GuideSpec.StateFrom(progressed, base, {}), {}), "mine") ~= nil)
	-- the restart baseline never makes counters negative
	check("relative stats are clamped at zero", GuideSpec.StateFrom(snap(), { BlocksDug = 50 }, {}).Stats.BlocksDug == 0)
end

-- ---------------------------------------------------------------- mine shift --------------------------------------
do
	local cfg = Config.Shift
	local deepest = Config.Layers[#Config.Layers].Id
	local function dep(total, deep, age) return { Total = total, ByLayer = { [deepest] = deep }, AgeMinutes = age } end
	check("fresh mine: no refresh", not ShiftSpec.ShouldRefresh(dep(0, 0, 0), cfg, deepest))
	check("half dug: no refresh yet", not ShiftSpec.ShouldRefresh(dep(0.4, 0.2, 10), cfg, deepest))
	check("mostly dug: refresh", ShiftSpec.ShouldRefresh(dep(cfg.TriggerFraction, 0.1, 5), cfg, deepest))
	check("deepest layer exhausted: refresh", ShiftSpec.ShouldRefresh(dep(0.2, cfg.DeepLayerFraction, 5), cfg, deepest))
	check("old but barely touched: no refresh", not ShiftSpec.ShouldRefresh(dep(0.02, 0, 500), cfg, deepest))
	check("old and meaningfully dug: refresh", ShiftSpec.ShouldRefresh(dep(cfg.MinFractionForAge, 0, cfg.MaxAgeMinutes), cfg, deepest))
end

-- ---------------------------------------------------------------- layer gating & progression data -----------------
do
	local layers = Config.Layers
	check("first layer is open to the starter tool", Defs.LayerAllows(Defs.Tools.rusty_shovel, layers[1]))
	check("second layer is open to the starter tool", Defs.LayerAllows(Defs.Tools.rusty_shovel, layers[2]))
	check("stone needs more than the starter", not Defs.LayerAllows(Defs.Tools.rusty_shovel, layers[3]) and not Defs.LayerAllows(Defs.Tools.digging_shovel, layers[3]))
	check("heavy shovel opens stone", Defs.LayerAllows(Defs.Tools.heavy_shovel, layers[3]))
	check("ruins need the jackhammer tier", not Defs.LayerAllows(Defs.Tools.power_shovel, layers[4]) and Defs.LayerAllows(Defs.Tools.jackhammer, layers[4]))
	check("tool name for a tier", Defs.ToolNameForTier(3) == "Heavy Shovel")
	local prev = -1
	for i, l in ipairs(layers) do
		check("layers deepen: " .. l.Id, l.FromCell > prev)
		prev = l.FromCell
		check("layer toughness rises: " .. l.Id, i == 1 or l.Health > layers[i - 1].Health)
		check("gating never goes backwards: " .. l.Id, i == 1 or (l.MinToolTier or 1) >= (layers[i - 1].MinToolTier or 1))
		local has = false
		for _, def in pairs(Defs.Treasure) do if def.Layers[l.Id] then has = true end end
		check("layer has discoveries: " .. l.Id, has)
	end
	check("mine is deeper than the old 14 rows", Config.Site.Depth >= 20)
	-- tools: price rises with tier; each tool tier has either a new layer or a new capability
	local last = -1
	for _, id in ipairs(Defs.ToolsByTier) do
		local t = Defs.Tools[id]
		check("price rises with tier: " .. id, t.Price > last)
		last = t.Price
	end
	-- no tier up-gate can strand a player: at least one layer is open to tier 1
	local anyOpen = false
	for _, l in ipairs(layers) do if (l.MinToolTier or 1) <= 1 then anyOpen = true end end
	check("the starter tool can always dig something", anyOpen)
	-- backpacks
	local packs = {}
	for id, p in pairs(Defs.Backpacks) do table.insert(packs, p) end
	table.sort(packs, function(a, b) return a.Order < b.Order end)
	for i, p in ipairs(packs) do
		check("pack has a model: " .. p.DisplayName, PackModels.Has(p.Appearance))
		check("pack capacity and price rise together: " .. p.DisplayName, i == 1 or (p.Capacity > packs[i - 1].Capacity and p.Price > packs[i - 1].Price))
	end
	check("five packs", #packs == 5)
end

print(("collection/guide/shift/progression: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
