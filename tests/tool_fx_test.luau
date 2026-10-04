-- Run: luau tests/tool_fx_test.luau   (after tests/prep_shared.py)
-- Checks the equipment effect PROFILES (pure data + gates) against the real tool catalogue. This proves the data and the rate/cap maths only:
-- how the effects look and sound in the engine is NOT tested here (docs/EFFECTS.md lists the Studio checks).
local stubs = require("./_build/shared/__stubs")
local ToolFx = require("./_build/shared/ToolFx")
local ToolModels = require("./_build/shared/ToolModels")
local Defs = require("./_build/shared/Defs")
local Config = require("./_build/shared/Config")
local _ = stubs

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. tostring(detail)) or "")) end
end

-- 1. stats are untouched (baseline recorded when the effects were added) ----------------------------------------------------------------
local BASELINE = {
	rusty_shovel = { 8, 2.0, 8 }, digging_shovel = { 12, 2.2, 8 }, heavy_shovel = { 36, 1.5, 8 }, power_shovel = { 36, 1.5, 8 },
	jackhammer = { 22, 4.5, 8 }, drill = { 22, 5.5, 11 }, industrial_drill = { 22, 5.5, 11 },
}
for id, b in pairs(BASELINE) do
	local d = Defs.Tools[id]
	check("stats unchanged " .. id, d and d.Power == b[1] and d.Rate == b[2] and d.Reach == b[3], id)
end

-- 2. every tool has its OWN profile; profiles are distinct ---------------------------------------------------------------------------------
local function describe(p)
	local keys = {}
	for k, v in pairs(p) do
		if k ~= "Name" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = p[k]
		if type(v) == "table" then
			local sub = {}
			for k2, v2 in pairs(v) do
				table.insert(sub, k2 .. "=" .. (type(v2) == "table" and "{..}" or tostring(v2)))
			end
			table.sort(sub)
			table.insert(parts, k .. "{" .. table.concat(sub, ",") .. "}")
		else
			table.insert(parts, k .. "=" .. tostring(v))
		end
	end
	return table.concat(parts, ";")
end
local seen = {}
local toolCount = 0
for id, def in pairs(Defs.Tools) do
	toolCount += 1
	local p = ToolFx.Profiles[id]
	check("profile exists: " .. id, p ~= nil)
	if p then
		check("profile is not generic: " .. id, p ~= ToolFx.Generic)
		check("dirt for every tool: " .. id, p.Dirt and p.Dirt.Impact >= 1 and p.Dirt.Break >= 1)
		check("sound defined: " .. id, p.Sound and p.Sound.Impact and p.Sound.Break)
		local d = describe(p)
		check("profile distinct: " .. id, seen[d] == nil, seen[d])
		seen[d] = id
		check("trail is brief: " .. id, p.Trail == nil or (p.Trail.Lifetime <= 0.15 and p.Trail.Transparency >= 0.3))
		check("dirt counts are modest: " .. id, p.Dirt.Impact <= 6 and p.Dirt.Break <= 16)
	end
end
check("seven tools, seven profiles", toolCount == 7)
for id in pairs(ToolFx.Profiles) do
	check("profile names a real tool: " .. id, Defs.Tools[id] ~= nil)
end
check("unknown / dynamite falls back to generic", ToolFx.For("dynamite") == ToolFx.Generic and ToolFx.For(nil) == ToolFx.Generic and ToolFx.For(12) == ToolFx.Generic)

-- 3. the requested progression ---------------------------------------------------------------------------------------------------------
local P = ToolFx.Profiles
local r, d, h, pr, j, dr, b = P.rusty_shovel, P.digging_shovel, P.heavy_shovel, P.power_shovel, P.jackhammer, P.drill, P.industrial_drill
check("starter: puff + chips, no trail/ring/sparks/streak/accent", r.Puff and not (r.Trail or r.Ring or r.Sparks or r.Streak or r.Accent))
check("improved: sharper (higher pitch) and short trail", d.Sound.Impact.Pitch > r.Sound.Impact.Pitch and d.Trail ~= nil and d.Dirt.Impact > r.Dirt.Impact)
check("reinforced: heavier sound, broader debris", h.Sound.Impact.Pitch < r.Sound.Impact.Pitch and (h.Dirt.Spread or 1) > 1 and h.Dirt.Break > d.Dirt.Break)
check("professional: teal accent + crisp streak", pr.Trail and pr.Trail.Color == "41BDAE" and pr.Streak and pr.Streak.Color == "41BDAE")
check("heavy excavation: ground ring + chunkier debris", j.Ring ~= nil and j.Dirt.Size > h.Dirt.Size and j.Dirt.BreakSize > pr.Dirt.BreakSize)
check("industrial: amber sparks, mechanical tick", dr.Sparks and dr.Sparks.Color == "FFB347" and dr.Sound.Tick ~= nil)
check("best: teal/brass strike + clean break accent", b.Ring and b.Ring.Color == "41BDAE" and b.Sparks and b.Sparks.Color == "D4A24A" and b.Accent and b.Dirt.Break <= r.Dirt.Break)
check("best tool has the highest tier", Defs.Tools.industrial_drill.Tier == 7)

-- 4. sparks suit stone / metal, soil gives dirt -------------------------------------------------------------------------------------------
for id, p in pairs(P) do
	check("no sparks on soil: " .. id, not ToolFx.SparksOn(p, "Soil"))
	check("no sparks on clay: " .. id, not ToolFx.SparksOn(p, "Clay"))
end
check("drill sparks on stone and ruins", ToolFx.SparksOn(dr, "Stone") and ToolFx.SparksOn(dr, "Ruins") and ToolFx.SparksOn(b, "Stone"))
check("hand tools never spark", not ToolFx.SparksOn(r, "Stone") and not ToolFx.SparksOn(d, "Ruins") and not ToolFx.SparksOn(h, "Stone"))

-- 5. area feedback matches the cells the server reports -----------------------------------------------------------------------------------
check("single-cell swing has no area feedback", ToolFx.AreaCells(pr, 1) == 0 and ToolFx.AreaCells(dr, 1) == 0)
check("area feedback equals the extra affected cells", ToolFx.AreaCells(pr, 3) == 2)
check("area feedback is capped", ToolFx.AreaCells(b, 14) == ToolFx.Caps.AreaCellsMax - 1)
check("no cells, no feedback", ToolFx.AreaCells(b, 0) == 0)

-- 6. fast tools never flood the screen: simulate 10 s of continuous mining ---------------------------------------------------------------------
for id, def in pairs(Defs.Tools) do
	local p = ToolFx.Profiles[id]
	local g, counts = {}, { Puff = 0, Sparks = 0, Ring = 0, Streak = 0 }
	local interval = 1 / def.Rate
	local t = 0
	while t < 10 do
		for kind in pairs(counts) do
			local spec = (kind == "Puff" and p.Puff) or p[kind]
			if spec and ToolFx.Gate(g, kind, t, ToolFx.GapFor(p, kind)) then
				counts[kind] += 1
			end
		end
		t += interval
	end
	check("rings per second bounded: " .. id, counts.Ring / 10 <= 1 / 0.27)
	check("streaks per second bounded: " .. id, counts.Streak / 10 <= 1 / 0.19)
	check("sparks bursts per second bounded: " .. id, counts.Sparks / 10 <= 1 / 0.11)
	check("big accents per second bounded: " .. id, (counts.Ring + counts.Streak) / 10 <= 7, (counts.Ring + counts.Streak) / 10)
	-- worst case: every swing breaks a block; debris lives <= 0.8 s
	local perSecond = (p.Dirt.Impact + p.Dirt.Break) * def.Rate + (p.Accent and p.Accent.Count * def.Rate or 0)
	check("live debris under the cap: " .. id, perSecond * 0.8 <= ToolFx.Caps.Chunks, perSecond * 0.8)
	local sparkLive = p.Sparks and (p.Sparks.Count * 2 * math.min(def.Rate, 1 / ToolFx.GapFor(p, "Sparks")) * 0.35) or 0
	check("live sparks under the cap: " .. id, sparkLive <= ToolFx.Caps.Sparks, sparkLive)
end
check("no lights from tool effects", ToolFx.Caps.LightsFor == 0)

-- 7. trail geometry comes from the real part spec ----------------------------------------------------------------------------------------------
for id, def in pairs(Defs.Tools) do
	local p = ToolFx.Profiles[id]
	if p.Trail then
		local spec = ToolModels.GetSpec(def.Appearance)
		local pts = ToolFx.RigPoints(spec.Parts, spec.Checks and spec.Checks.WorkingEnd)
		local top = -1e9
		for _, part in ipairs(spec.Parts) do
			local r = part.Offset
			local ey = math.abs(r.RightVector.Y) * part.Size.X / 2 + math.abs(r.UpVector.Y) * part.Size.Y / 2 + math.abs(r.LookVector.Y) * part.Size.Z / 2
			top = math.max(top, r.Position.Y + ey)
		end
		check("trail anchored at the working end: " .. id, pts.Tip.Y > 1.5 and pts.Tip.Y >= top - 0.7, pts.Tip.Y .. " vs top " .. top)
		check("trail spans the blade: " .. id, pts.B.X > pts.A.X and (pts.B.X - pts.A.X) <= 2.3, pts.B.X - pts.A.X)
	end
end

-- 8. the trail is only on during the strike -------------------------------------------------------------------------------------------------------
for _, dur in ipairs({ 0.1, 0.18, 0.25, 0.45, 0.5 }) do
	local s, l = ToolFx.StrikeWindow(dur)
	check("strike window inside the swing " .. dur, s > 0 and s + l <= dur and l <= ToolFx.MaxStrike)
end

-- 9. gate behaviour ----------------------------------------------------------------------------------------------------------------------------------
local g = {}
check("gate first fire", ToolFx.Gate(g, "x", 0, 0.2))
check("gate blocks inside gap", not ToolFx.Gate(g, "x", 0.1, 0.2))
check("gate reopens after gap", ToolFx.Gate(g, "x", 0.25, 0.2))
check("gap floor", ToolFx.GapFor({ MinGap = { Puff = 0.0 } }, "Puff") >= 0.08)
local _cfg = Config

print(("tool_fx_test: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tool_fx_test failed") end
