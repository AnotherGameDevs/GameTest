-- Run via tests/run_all.sh. BEHAVIOUR tests for buried loot and the mine reset lifecycle (no model coordinates here).
local Config = require("./_build/shared/Config")
local Defs = require("./_build/shared/Defs")
local Grid = require("./_build/shared/Grid")
local LootPlan = require("./_build/shared/LootPlan")
local LootBoard = require("./_build/shared/LootBoard")
local MineLifecycle = require("../src/server/Services/MineLifecycle")
local Records = require("../src/server/Services/ArtifactRecords")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

local function newRng(seed)
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	return { NextNumber = function() s = (s * 48271) % 2147483647; return s / 2147483647 end }
end
local function plan(seed) return LootPlan.Generate(newRng(seed), seed) end

local SEEDS = {}
for i = 1, 24 do SEEDS[i] = i * 104729 + 17 end

-- ================================================================== fresh seed -> fresh placement ==================
do
	local a, b, a2 = plan(SEEDS[1]), plan(SEEDS[2]), plan(SEEDS[1])
	local same, diff, total = 0, 0, 0
	for idx, id in pairs(a.Loot) do
		total += 1
		if b.Loot[idx] == id then same += 1 end
		if a2.Loot[idx] ~= id then diff += 1 end
	end
	check("the same seed rebuilds the same board (a rejoin can never change it: nothing re-rolls it)", diff == 0)
	check("a different seed gives a different board", same / total < 0.2, ("%.2f identical"):format(same / total))
	local identicalAll = true
	for i = 2, #SEEDS do
		local p = plan(SEEDS[i])
		for idx, id in pairs(a.Loot) do if p.Loot[idx] ~= id then identicalAll = false; break end end
	end
	check("no permanent profitable coordinates: boards differ across every seed", not identicalAll)
	check("the fixed cosmetic seed is not the loot seed", Config.Site.Seed == 1337)
	local constBoard = plan(Config.Site.Seed)
	local diffFromConst = 0
	for idx, id in pairs(a.Loot) do if constBoard.Loot[idx] ~= id then diffFromConst += 1 end end
	check("a fresh seed does not reproduce the old constant-seed layout", diffFromConst / total > 0.7)
end

-- ================================================================== layer rules, ordinary rewards =================
do
	local p = plan(SEEDS[3])
	local bad, ordinary, total = 0, 0, 0
	for idx, id in pairs(p.Loot) do
		local _, y = Grid.FromIndex(idx)
		local layer = Defs.LayerAtCell(y)
		total += 1
		if not Defs.Treasure[id].Layers[layer.Id] then bad += 1 end
		if not Defs.Treasure[id].RequiresCarry then ordinary += 1 end
	end
	check("every reward is allowed in its layer's weighted table", bad == 0, tostring(bad))
	check("ordinary rewards stay plentiful (mining stays worthwhile)", ordinary > 1500 and ordinary / total > 0.95, ("%d of %d"):format(ordinary, total))
end

-- ================================================================== important artifacts ============================
do
	local worstOver, ineligible, perGenClaw = 0, 0, {}
	for _, seed in ipairs(SEEDS) do
		local p = plan(seed)
		for id, n in pairs(p.Counts) do
			local def = Defs.Treasure[id]
			if def.RequiresCarry then
				local limit = Config.Loot.ImportantLimits[id] or Config.Loot.DefaultImportantLimit
				if n > limit then worstOver = math.max(worstOver, n - limit) end
			end
		end
		for idx, id in pairs(p.Loot) do
			if Defs.Treasure[id].RequiresCarry then
				local x, y, z = Grid.FromIndex(idx)
				if not LootPlan.Eligible(x, y, z) then ineligible += 1 end
			end
		end
		table.insert(perGenClaw, p.Counts.fossil_claw or 0)
	end
	check("important artifacts never exceed their per-generation limits", worstOver == 0)
	check("important artifacts only sit in eligible cells (inside the grid, off bedrock, away from the elevator side)", ineligible == 0)
	check("limits are configurable per artifact", Config.Loot.ImportantLimits.sun_mask == 1 and Config.Loot.ImportantLimits.fossil_claw > Config.Loot.ImportantLimits.sun_mask)
	local reaches = 0
	for _, n in ipairs(perGenClaw) do if n == Config.Loot.ImportantLimits.fossil_claw then reaches += 1 end end
	check("the limit is actually used (artifacts exist in most generations)", reaches >= #SEEDS * 0.7, tostring(reaches))

	-- survivors are chosen uniformly among candidates, not "first cells in index order"
	local saved = {}
	for k, v in pairs(Config.Loot.ImportantLimits) do saved[k] = v end
	local candY, keptY, candN, keptN = 0, 0, 0, 0
	for _, seed in ipairs(SEEDS) do
		Config.Loot.ImportantLimits.fossil_claw = 100000
		local all = plan(seed)
		for k, v in pairs(saved) do Config.Loot.ImportantLimits[k] = v end
		local lim = plan(seed)
		for idx, id in pairs(all.Loot) do if id == "fossil_claw" then local _, y = Grid.FromIndex(idx); candY += y; candN += 1 end end
		for idx, id in pairs(lim.Loot) do if id == "fossil_claw" then local _, y = Grid.FromIndex(idx); keptY += y; keptN += 1 end end
	end
	for k, v in pairs(saved) do Config.Loot.ImportantLimits[k] = v end
	check("limited survivors are unbiased by depth (mean row within 1.5 of all candidates)", keptN > 0 and math.abs(candY / candN - keptY / keptN) < 1.5,
		("candidates %.2f vs kept %.2f"):format(candY / candN, keptY / keptN))
end

-- ================================================================== random pockets ================================
do
	local firsts = {}
	for _, seed in ipairs(SEEDS) do
		local p = plan(seed)
		local key = {}
		for _, pocket in ipairs(p.Pockets) do table.insert(key, pocket.Kind .. pocket.Cells[1][1] .. "," .. pocket.Cells[1][2] .. "," .. pocket.Cells[1][3]) end
		firsts[table.concat(key, "|")] = true
	end
	local distinct = 0
	for _ in pairs(firsts) do distinct += 1 end
	check("pocket positions are different in every generation", distinct == #SEEDS, tostring(distinct))
	local p = plan(SEEDS[5])
	local lootInPockets = 0
	for _, pocket in ipairs(p.Pockets) do for _, c in ipairs(pocket.Cells) do if c[4] and p.Loot[Grid.ToIndex(c[1], c[2], c[3])] == c[4] then lootInPockets += 1 end end end
	check("pocket cells own their configured loot", lootInPockets >= 8)
end

-- ================================================================== exactly-once claims, generations ==============
do
	local board = LootBoard.new(3, { [10] = "old_coin", [11] = "golden_scarab" })
	check("a reward is claimed exactly once", board:Claim(10, 3) == "old_coin" and board:Claim(10, 3) == nil)
	check("empty cells give nothing", board:Claim(99, 3) == nil)
	check("a claim from an old generation fails", board:Claim(11, 2) == nil and board:Peek(11) == "golden_scarab")
	check("a claim from a future generation fails", board:Claim(11, 4) == nil)
	check("the right generation can still claim it", board:Claim(11, 3) == "golden_scarab" and board:Remaining() == 0)
	-- old requests vs a NEW mine with loot at the same coordinates
	local fresh = LootBoard.new(4, { [10] = "cut_gemstone" })
	check("an old-generation request cannot take loot at matching coordinates in the new mine", fresh:Claim(10, 3) == nil and fresh:Peek(10) == "cut_gemstone")
	check("two simultaneous claims: only the first succeeds", (function()
		local b = LootBoard.new(1, { [5] = "pottery_shard" })
		local got = {}
		for i = 1, 5 do got[i] = b:Claim(5, 1) end
		return got[1] == "pottery_shard" and got[2] == nil and got[5] == nil
	end)())
end

-- ================================================================== reset lifecycle ================================
do
	local P = Config.Reset
	local t = 1000
	local L = MineLifecycle.new(P, t)
	check("starts Active, generation 1, accepting requests", L:State() == "Active" and L:Generation() == 1 and L:AcceptingRequests())
	-- helper: advance simulated seconds one at a time
	local function run(seconds, depletion, players)
		local events = {}
		for _ = 1, seconds do
			t += 1
			local e = L:Update(t, depletion, players)
			if e then table.insert(events, e) end
		end
		return events
	end
	check("no reset on an idle, fresh mine", #run(300, 0.1, 2) == 0 and L:State() == "Active")
	check("depletion before the minimum lifetime does NOT trigger a reset", #run(200, 0.95, 2) == 0 and L:State() == "Active")
	local ev = run(120, 0.95, 2) -- active time now ~620 s (> 10 minutes): depletion may trigger
	check("depletion after the minimum lifetime starts the warning", ev[1] == "Warn" and L:State() == "Warning" and L:Reason() == "Depleted")
	check("mining and pickups are still accepted during the warning", L:AcceptingRequests())
	check("a second trigger during the warning is ignored (no overlap)", #run(5, 1, 2) == 0 and L:State() == "Warning")
	local ev2 = run(P.WarningSeconds, 1, 2)
	check("the warning ends in an evacuation", ev2[1] == "Evacuate" and L:State() == "Evacuating")
	check("requests are refused from the deadline on", not L:AcceptingRequests())
	check("evacuation cannot be restarted or skipped past regeneration", not L:FinishRegeneration(t) and #run(30, 1, 2) == 0 and L:State() == "Evacuating")
	check("regeneration only follows evacuation", L:BeginRegeneration() and L:State() == "Regenerating" and not L:AcceptingRequests() and not L:BeginRegeneration())
	check("requests stay refused while regenerating", not L:AcceptingRequests())
	check("finishing creates a NEW generation and returns to Active", L:FinishRegeneration(t) and L:State() == "Active" and L:Generation() == 2 and L:AcceptingRequests())
	check("finishing twice is impossible", not L:FinishRegeneration(t) and L:Generation() == 2)
	check("an old generation id is no longer current", not L:IsCurrent(1) and L:IsCurrent(2))
	check("timers reset: a fully depleted NEW mine does not reset instantly", #run(60, 1, 2) == 0 and L:State() == "Active")

	-- scheduled reset
	local S = MineLifecycle.new(P, 0)
	local warnAt
	for sec = 1, P.IntervalMinutes * 60 + 5 do
		if S:Update(sec, 0, 1) == "Warn" and not warnAt then warnAt = sec end
	end
	check("a scheduled reset starts after the configured interval of active play", warnAt == P.IntervalMinutes * 60 and S:Reason() == "Scheduled", tostring(warnAt))
	-- empty server: the clock pauses
	local E = MineLifecycle.new(P, 0)
	local fired = false
	for sec = 1, P.IntervalMinutes * 60 * 3 do if E:Update(sec, 1, 0) then fired = true end end
	check("an empty server never resets (the clock pauses)", not fired and E:SecondsToScheduled() == P.IntervalMinutes * 60)

	-- reset loops: a permanently depleted mine still resets at most once per MinLifetime + warning + evacuation
	local R = MineLifecycle.new(P, 0)
	local warns, simTime = {}, 0
	for sec = 1, 3 * 3600 do
		simTime = sec
		local e = R:Update(sec, 1, 3)
		if e == "Warn" then table.insert(warns, sec) end
		if e == "Evacuate" then R:BeginRegeneration(); R:FinishRegeneration(sec) end
	end
	local minGap = 1e9
	for i = 2, #warns do minGap = math.min(minGap, warns[i] - warns[i - 1]) end
	check("reset loops are impossible: spacing never below the minimum lifetime", #warns >= 5 and minGap >= P.MinLifetimeMinutes * 60 + P.WarningSeconds, ("%d resets, min gap %d s"):format(#warns, minGap))
	check("policy values", P.IntervalMinutes == 20 and P.DepletionFraction == 0.70 and P.MinLifetimeMinutes == 10 and P.WarningSeconds == 60)
end

-- ================================================================== recovery never deposits or duplicates ==========
do
	local n = 0
	local store = Records.new(function() n += 1; return "R" .. n end)
	local pad = { X = 99 }
	local carried = store:Create("golden_scarab", 1400, 1, { X = 0 }, 1)
	store:Pickup(carried.Id, 1)
	local placed = store:Create("fossil_claw", 900, 2, { X = 1 }, 1)
	local deposited = store:Create("sun_mask", 3500, 3, { X = 2 }, 1)
	store:Pickup(deposited.Id, 3); store:Deposit(deposited.Id, 3)
	local before = 0
	for _ in pairs(store.records) do before += 1 end

	check("recovering a carried artifact puts it down at the recovery area, still owned, flagged", store:Recover(carried.Id, pad) and carried.State == "Dropped" and carried.Position == pad and carried.OwnerId == 1 and carried.Recovered)
	check("the carrier is no longer 'carrying' it", store:CarriedBy(1) == nil)
	check("recovering a placed artifact moves it, still owned", store:Recover(placed.Id, pad) and placed.State == "Dropped" and placed.OwnerId == 2 and placed.Recovered)
	check("recovery never pays out or deposits anything", carried.State ~= "Deposited" and placed.State ~= "Deposited")
	check("a deposited artifact can not be recovered (so it can not be duplicated)", not store:Recover(deposited.Id, pad) and deposited.State == "Deposited")
	local after = 0
	for _ in pairs(store.records) do after += 1 end
	check("no records are created or lost", before == after)
	check("only the owner can pick a recovered artifact up", not store:Pickup(carried.Id, 2) and store:Pickup(carried.Id, 1))
	local ok, value = store:Deposit(carried.Id, 1)
	check("the owner delivers it: paid exactly once", ok and value == 1400 and not store:Deposit(carried.Id, 1))
	check("recovering twice is harmless", store:Recover(placed.Id, pad) and #store:Dropped() == 1)
end

print(("loot + reset behaviour: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
