-- Polished chunky models for notable artifacts. Treasures without a Model id keep the generic coin/ring/gem/block
-- placeholder built by EffectsController. All models are ~2-2.8 studs across so reveal animations need no changes.
local Kit = require(script.Parent.ModelKit)
local Config = require(script.Parent.Config)

local TreasureModels = {}

local V = Vector3.new
local function hex(s: string): Color3
	return Color3.fromHex(s)
end
local P = Config.Palette
local GOLD, GOLD_DARK = P.Gold, hex("C98A1E")
local TEAL = P.Teal

local builders = {}

-- Epic. Golden scarab: stretched-sphere shell with a split wing line, six chunky legs, teal eyes and a teal sun gem.
function builders.scarab()
	local parts = {
		Kit.ellipsoid("Shell", V(2.2, 1.3, 2.8), V(0, 0, 0.1), GOLD, Enum.Material.SmoothPlastic),
		Kit.ellipsoid("Head", V(1.3, 0.8, 0.95), V(0, -0.05, -1.6), GOLD_DARK),
		Kit.block("WingSplit", V(0.12, 0.14, 2.2), V(0, 0.64, 0.25), GOLD_DARK),
		Kit.ball("SunGem", 0.6, V(0, 0.62, -0.55), TEAL, Enum.Material.Neon),
		Kit.ball("EyeL", 0.3, V(-0.36, 0.08, -2.0), TEAL, Enum.Material.Neon),
		Kit.ball("EyeR", 0.3, V(0.36, 0.08, -2.0), TEAL, Enum.Material.Neon),
	}
	for i, z in ipairs({ -0.7, 0.25, 1.15 }) do
		for _, side in ipairs({ -1, 1 }) do
			table.insert(parts, Kit.block(("Leg%d_%d"):format(i, side), V(0.9, 0.28, 0.34),
				V(side * 1.35, -0.45, z), GOLD_DARK, Enum.Material.SmoothPlastic, V(0, side * (20 - i * 12), side * -12)))
		end
	end
	return parts
end

-- Rare. Cut gemstone: stepped brilliant-cut (crown, table, pavilion, culet), turned 45 degrees so it reads as a
-- diamond from any side.
function builders.gem()
	local crown, mid, deep = hex("7FE3FF"), hex("4DD2FF"), hex("2AA3D6")
	local function layer(name: string, size: number, h: number, y: number, color: Color3)
		return Kit.block(name, V(size, h, size), V(0, y, 0), color, Enum.Material.Neon, V(0, 45, 0))
	end
	return {
		layer("Girdle", 1.9, 0.25, 0, mid),
		layer("Crown1", 1.55, 0.3, 0.27, crown),
		layer("Crown2", 1.1, 0.3, 0.55, crown),
		layer("Table", 0.65, 0.2, 0.78, hex("D9F6FF")),
		layer("Pav1", 1.55, 0.3, -0.27, mid),
		layer("Pav2", 1.1, 0.3, -0.55, deep),
		layer("Pav3", 0.7, 0.3, -0.83, deep),
		layer("Culet", 0.3, 0.2, -1.05, deep),
	}
end

-- Rare. Ancient necklace: gold bead loop with a teal pendant in a gold frame. Faces +/-Z.
function builders.necklace()
	local parts = {}
	local r = 1.05
	local n = 0
	for deg = 0, 360, 24 do
		-- phi measured from the top going round; leave a gap at the bottom for the pendant
		if deg <= 148 or deg >= 212 then
			n += 1
			local phi = math.rad(deg)
			local accent = (n % 3 == 0)
			table.insert(parts, Kit.ball("Bead" .. n, accent and 0.5 or 0.4, V(math.sin(phi) * r, math.cos(phi) * r, 0),
				accent and GOLD_DARK or GOLD))
		end
	end
	table.insert(parts, Kit.block("Frame", V(0.95, 0.95, 0.3), V(0, -1.3, 0), GOLD, Enum.Material.SmoothPlastic, V(0, 0, 45)))
	table.insert(parts, Kit.block("PendantGem", V(0.6, 0.6, 0.36), V(0, -1.3, 0), TEAL, Enum.Material.Neon, V(0, 0, 45)))
	table.insert(parts, Kit.ball("Hook", 0.36, V(0, 1.2, 0), GOLD_DARK))
	return parts
end

-- Generic stand-ins for treasures that do not have a polished model yet.
local function genericSpecs(def)
	local c = def.Color
	if def.Shape == "Coin" then
		return { Kit.cyl("Body", "X", 0.5, 2.4, V(0, 0, 0), c) }
	elseif def.Shape == "Ring" then
		return { Kit.cyl("Body", "X", 0.8, 2.4, V(0, 0, 0), c) }
	elseif def.Shape == "Gem" then
		return { Kit.block("Body", V(1.8, 1.8, 1.8), V(0, 0, 0), c, Enum.Material.Neon) }
	end
	return { Kit.block("Body", V(2.2, 1.6, 1.8), V(0, 0, 0), c) }
end

-- Part specs (origin-centred) for a treasure id, polished or generic. `Defs` is passed in to avoid a require
-- cycle (Defs does not depend on this module, but callers already hold it).
function TreasureModels.Specs(treasureId: string, def)
	local builder = def.Model and builders[def.Model]
	if builder then
		return builder()
	end
	return genericSpecs(def)
end

-- Anchored, ready-to-animate Model (PrimaryPart "Root" at the origin). Always succeeds.
function TreasureModels.BuildAny(treasureId: string, def): Model
	return Kit.BuildModel(TreasureModels.Specs(treasureId, def), treasureId)
end

-- Kept for callers that only want polished models.
function TreasureModels.Build(modelId: string?): Model?
	local builder = modelId and builders[modelId]
	if not builder then
		return nil
	end
	return Kit.BuildModel(builder(), modelId)
end

return TreasureModels
