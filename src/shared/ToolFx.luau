-- Effect PROFILES for the mining tools: purely cosmetic data, one entry per tool in Defs.Tools. Stats (power, rate, reach, splash) live in
-- Defs and are never touched here. Pure, so tests/tool_fx_test.luau can check it outside Roblox.
--
-- What an effect may depend on: the tool id (from the server's result), the layer of the cell that was hit or broken (Soil/Clay/Stone/Ruins),
-- and how many cells the server says were affected. It must NEVER depend on a block's hidden reward, rarity or loot assignment: no function in
-- this file or in ToolFxController takes loot information (guarded by tests and tools/preflight.py).
--
-- Colours are hex strings (converted by the client). Mapping to the catalogue (seven tools -> seven profiles, in tier order):
--   1 Rusty Shovel -> Starter          2 Digging Shovel -> Improved hand tool   3 Heavy Shovel -> Reinforced
--   4 Power Shovel -> Professional     5 Jackhammer -> Heavy excavation         6 Drill -> Industrial
--   7 Industrial Drill -> Best tool
-- To re-assign a profile to another tool, change the key only.
local ToolFx = {}

ToolFx.Caps = {
	Chunks = 140, -- live dirt/debris parts (client total)
	Sparks = 22, -- live spark parts
	Rings = 2, -- live ground rings
	Streaks = 2, -- live cutting streaks
	LightsFor = 0, -- no point lights are ever created by tool effects
	OtherPlayerChunkScale = 0.5, -- other players' effects are a restrained version of your own
	OtherPlayerMaxDistance = 90, -- studs: further than this, other players' tool effects are skipped
	AreaCellsMax = 4, -- most cells that get area feedback from one swing
}

local EARTH = "9A7B5A"
local TEAL, BRASS = "41BDAE", "D4A24A"

ToolFx.Profiles = {
	rusty_shovel = {
		Name = "Starter",
		Dirt = { Impact = 3, Break = 8, Speed = 11, BreakSpeed = 20, Size = 0.55, BreakSize = 1.0 },
		Puff = { Color = EARTH, Size = 1.4 }, -- small earthy puff at the impact point
		Sound = { Impact = { Pitch = 0.95, Volume = 0.8 }, Break = { Pitch = 0.95, Volume = 0.85 } }, -- dry
		MinGap = { Puff = 0.12 },
	},
	digging_shovel = {
		Name = "Improved hand tool",
		Dirt = { Impact = 4, Break = 10, Speed = 15, BreakSpeed = 23, Size = 0.6, BreakSize = 1.1 },
		Puff = { Color = EARTH, Size = 1.7 },
		Sound = { Impact = { Pitch = 1.12, Volume = 0.85 }, Break = { Pitch = 1.05, Volume = 0.9 } }, -- sharper
		Trail = { Color = "D8DEE6", Width = 0.35, Lifetime = 0.12, Transparency = 0.45 }, -- short blade trail, strike only
		MinGap = { Puff = 0.1 },
	},
	heavy_shovel = {
		Name = "Reinforced",
		Dirt = { Impact = 5, Break = 14, Speed = 14, BreakSpeed = 26, Size = 0.75, BreakSize = 1.35, Spread = 1.5 }, -- broader burst
		Puff = { Color = EARTH, Size = 2.2 },
		Sound = { Impact = { Pitch = 0.7, Volume = 1.0 }, Break = { Pitch = 0.72, Volume = 1.0 } }, -- heavier
		MinGap = { Puff = 0.15 },
	},
	power_shovel = {
		Name = "Professional",
		Dirt = { Impact = 4, Break = 12, Speed = 15, BreakSpeed = 25, Size = 0.65, BreakSize = 1.2 },
		Puff = { Color = EARTH, Size = 1.8 },
		Sound = { Impact = { Pitch = 1.0, Volume = 0.85 }, Break = { Pitch = 1.0, Volume = 0.95 } },
		Trail = { Color = TEAL, Width = 0.3, Lifetime = 0.1, Transparency = 0.4 },
		Streak = { Color = TEAL, Length = 3.2, Time = 0.14 }, -- crisp cutting streak on the strike
		Area = "controlled",
		MinGap = { Puff = 0.12, Streak = 0.2 },
	},
	jackhammer = {
		Name = "Heavy excavation",
		Dirt = { Impact = 5, Break = 15, Speed = 15, BreakSpeed = 27, Size = 0.9, BreakSize = 1.6, Spread = 1.3 }, -- chunkier debris
		Puff = { Color = EARTH, Size = 2.0 },
		Ring = { Color = "C9B89A", Radius = 3.4, Time = 0.22, On = "both", MinGap = 0.3 }, -- brief ground-level impact ring
		Sound = { Impact = { Pitch = 0.62, Volume = 0.95 }, Break = { Pitch = 0.62, Volume = 1.0 } },
		Area = "controlled",
		MinGap = { Puff = 0.12, Ring = 0.3 },
	},
	drill = {
		Name = "Industrial",
		Dirt = { Impact = 3, Break = 11, Speed = 14, BreakSpeed = 24, Size = 0.6, BreakSize = 1.1 },
		Puff = { Color = EARTH, Size = 1.5 },
		Sparks = { Color = "FFB347", Count = 4, Speed = 17, Layers = { Stone = true, Ruins = true }, MinGap = 0.12 }, -- sparks only on stone / ruins
		Sound = { Impact = { Pitch = 1.3, Volume = 0.8 }, Break = { Pitch = 0.9, Volume = 0.95 }, Tick = { Pitch = 1.9, Volume = 0.3, MinGap = 0.18 } }, -- mechanical accent
		Area = "controlled",
		MinGap = { Puff = 0.14, Sparks = 0.12 },
	},
	industrial_drill = {
		Name = "Best tool",
		Dirt = { Impact = 3, Break = 8, Speed = 14, BreakSpeed = 24, Size = 0.55, BreakSize = 1.0 }, -- clean: fewer, tidier pieces
		Puff = { Color = "BFD8D2", Size = 1.4 },
		Sparks = { Color = BRASS, Count = 4, Speed = 18, Layers = { Stone = true, Ruins = true }, MinGap = 0.14 },
		Ring = { Color = TEAL, Radius = 2.4, Time = 0.18, On = "impact", MinGap = 0.28, Flat = true }, -- teal strike ring
		Streak = { Color = BRASS, Length = 3.6, Time = 0.14 },
		Accent = { Color = TEAL, Count = 5 }, -- teal/brass break burst
		Trail = { Color = TEAL, Width = 0.32, Lifetime = 0.11, Transparency = 0.4 },
		Sound = { Impact = { Pitch = 1.15, Volume = 0.85 }, Break = { Pitch = 1.1, Volume = 0.95 }, Tick = { Pitch = 1.6, Volume = 0.3, MinGap = 0.2 } },
		Area = "controlled",
		MinGap = { Puff = 0.14, Sparks = 0.14, Ring = 0.28, Streak = 0.22 },
	},
}

-- Not a tool: the plain dirt feedback used for blocks broken by something that is not a mining tool (dynamite) and for an unknown id.
ToolFx.Generic = {
	Name = "Generic",
	Dirt = { Impact = 4, Break = 10, Speed = 14, BreakSpeed = 24, Size = 0.7, BreakSize = 1.3 },
	Puff = { Color = EARTH, Size = 1.6 },
	Sound = { Impact = { Pitch = 1.0, Volume = 0.8 }, Break = { Pitch = 1.0, Volume = 0.9 } },
	MinGap = { Puff = 0.12 },
}

-- Profile for a tool id; an unknown id (a future tool, dynamite, a bad payload) gets the generic dirt feedback rather than erroring.
function ToolFx.For(toolId: any)
	return ToolFx.Profiles[toolId] or ToolFx.Generic
end

-- The strike part of a swing of total length `duration`, as (start, length) in seconds. Matches the viewmodel thrust (30%..50% of the
-- swing, ViewmodelMath.Swing) and the third-person grip tween; a short tail lets the trail finish. Never longer than MaxStrike.
ToolFx.MaxStrike = 0.2
function ToolFx.StrikeWindow(duration: number): (number, number)
	local d = math.max(duration, 0.1)
	return d * 0.28, math.min(d * 0.26, ToolFx.MaxStrike)
end

-- Does this effect kind apply on this layer? Sparks only on stone/ruins; dirt on every layer. `layerId` comes from the cell's DEPTH only.
function ToolFx.SparksOn(profile, layerId: string): boolean
	return profile.Sparks ~= nil and profile.Sparks.Layers[layerId] == true
end

-- How many extra cells get feedback for a result: exactly the cells the server reported (minus the first), capped. A tool that did not
-- affect several cells never gets area feedback, whatever its profile says.
function ToolFx.AreaCells(profile, affected: number): number
	if affected <= 1 then
		return 0
	end
	return math.min(affected - 1, ToolFx.Caps.AreaCellsMax - 1)
end

-- Time-based gate: true if `key` may fire at `now` given its minimum gap; records the firing. `state` is a plain table.
function ToolFx.Gate(state, key: string, now: number, minGap: number): boolean
	local last = state[key]
	if last and now - last < minGap then
		return false
	end
	state[key] = now
	return true
end

-- Gap (seconds) the profile asks for between two firings of `kind`, never shorter than a floor so very fast tools cannot flood the screen.
function ToolFx.GapFor(profile, kind: string): number
	local floor = 0.08
	local gap = profile.MinGap and profile.MinGap[kind] or 0.1
	return math.max(gap, floor)
end

-- Where the blade trail is anchored on a tool, from the REAL part spec (the same spec the held tool and viewmodel are built from).
-- Returns two points across the working end (tool space: +Y forward, +X width) and the tip. `parts` is the spec's Parts list;
-- `names` is spec.Checks.WorkingEnd. Falls back to the model's furthest-forward part if a name is missing.
function ToolFx.RigPoints(parts, names)
	local function extent(p)
		local r = p.Offset
		local hx, hy, hz = p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2
		local rx, ry, rz = r.RightVector, r.UpVector, r.LookVector -- the part's local axes in tool space
		local ex = math.abs(rx.X) * hx + math.abs(ry.X) * hy + math.abs(rz.X) * hz
		local ey = math.abs(rx.Y) * hx + math.abs(ry.Y) * hy + math.abs(rz.Y) * hz
		return ex, ey, r.Position
	end
	local topY, widthSum, count, centreX = -1e9, 0, 0, 0
	local wanted = {}
	for _, n in ipairs(names or {}) do
		wanted[n] = true
	end
	for _, p in ipairs(parts) do
		if wanted[p.Name] then
			local ex, ey, c = extent(p)
			topY = math.max(topY, c.Y + ey)
			widthSum = math.max(widthSum, ex)
			centreX += c.X
			count += 1
		end
	end
	if count == 0 then
		for _, p in ipairs(parts) do
			local _, ey, c = extent(p)
			if c.Y + ey > topY then
				topY = c.Y + ey
			end
		end
		widthSum = 0.5
		count = 1
	end
	local half = math.clamp(widthSum * 0.9, 0.25, 1.1)
	local cx = centreX / count
	return { A = { X = cx - half, Y = topY, Z = 0 }, B = { X = cx + half, Y = topY, Z = 0 }, Tip = { X = cx, Y = topY, Z = 0 } }
end

return ToolFx
