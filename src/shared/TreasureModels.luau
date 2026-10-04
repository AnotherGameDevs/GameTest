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

-- Epic. Fossil claw: three tapering, curving segments in bone colour with a dark tip, on a small stone base.
function builders.claw()
	local BONE, BONE_DARK = P.Cream, hex("B9A57E")
	return {
		Kit.block("Base", V(1.9, 0.4, 1.3), V(0, -1.15, 0), hex("8A8F96"), Enum.Material.Slate),
		Kit.block("Seg1", V(0.9, 1.1, 0.8), V(-0.15, -0.45, 0), BONE, Enum.Material.SmoothPlastic, V(0, 0, 8)),
		Kit.block("Seg2", V(0.72, 1.0, 0.64), V(0.2, 0.45, 0), BONE, Enum.Material.SmoothPlastic, V(0, 0, -14)),
		Kit.block("Seg3", V(0.52, 0.9, 0.46), V(0.75, 1.2, 0), BONE_DARK, Enum.Material.SmoothPlastic, V(0, 0, -38)),
		Kit.block("Tip", V(0.3, 0.55, 0.3), V(1.3, 1.6, 0), hex("5A4A33"), Enum.Material.SmoothPlastic, V(0, 0, -58)),
	}
end

-- Rare. Ruin tablet: a slab of sandstone with carved glyph rows and a chipped corner. Faces +/-Z.
function builders.tablet()
	local SAND, CARVE = P.Sandstone, hex("8C6B3E")
	local parts = {
		Kit.block("Slab", V(2.0, 2.6, 0.5), V(0, 0, 0), SAND, Enum.Material.Sandstone),
		Kit.block("Chip", V(0.7, 0.7, 0.52), V(0.85, 1.2, 0), hex("2B2F36"), Enum.Material.SmoothPlastic, V(0, 0, 45)),
	}
	for i = 1, 4 do
		table.insert(parts, Kit.block("Glyph" .. i, V(i % 2 == 0 and 1.3 or 1.0, 0.18, 0.54), V(-0.1, 0.95 - i * 0.45, 0), CARVE))
	end
	return parts
end

-- Legendary. Sun pharaoh mask: a gold headdress with teal stripes, eyes, a nose bridge and a beard. Faces +Z.
function builders.mask()
	local STRIPE = hex("2D6FB5")
	return {
		Kit.block("Face", V(1.7, 2.2, 0.8), V(0, 0, 0), GOLD, Enum.Material.SmoothPlastic),
		Kit.block("HeadCloth", V(2.5, 1.0, 1.1), V(0, 1.2, -0.1), GOLD_DARK, Enum.Material.SmoothPlastic),
		Kit.block("SideL", V(0.55, 2.4, 0.9), V(-1.4, -0.1, -0.1), GOLD_DARK, Enum.Material.SmoothPlastic),
		Kit.block("SideR", V(0.55, 2.4, 0.9), V(1.4, -0.1, -0.1), GOLD_DARK, Enum.Material.SmoothPlastic),
		Kit.block("StripeL", V(0.2, 2.0, 0.92), V(-1.4, -0.1, -0.1), STRIPE, Enum.Material.SmoothPlastic),
		Kit.block("StripeR", V(0.2, 2.0, 0.92), V(1.4, -0.1, -0.1), STRIPE, Enum.Material.SmoothPlastic),
		Kit.block("Brow", V(1.5, 0.22, 0.2), V(0, 0.45, 0.42), STRIPE, Enum.Material.SmoothPlastic),
		Kit.block("EyeL", V(0.45, 0.28, 0.2), V(-0.42, 0.2, 0.42), TEAL, Enum.Material.Neon),
		Kit.block("EyeR", V(0.45, 0.28, 0.2), V(0.42, 0.2, 0.42), TEAL, Enum.Material.Neon),
		Kit.block("Nose", V(0.3, 0.8, 0.3), V(0, -0.2, 0.5), GOLD_DARK, Enum.Material.SmoothPlastic),
		Kit.block("Mouth", V(0.7, 0.14, 0.2), V(0, -0.78, 0.42), GOLD_DARK, Enum.Material.SmoothPlastic),
		Kit.block("Beard", V(0.5, 0.9, 0.4), V(0, -1.5, 0.2), STRIPE, Enum.Material.SmoothPlastic),
		Kit.ball("CrownGem", 0.5, V(0, 1.55, 0.45), TEAL, Enum.Material.Neon),
	}
end

-- Uncommon. Clay figurine: a squat body, round head and stubby arms on a base.
function builders.figurine()
	local CLAY = P.Sandstone
	return {
		Kit.block("Base", V(1.4, 0.3, 1.0), V(0, -1.1, 0), P.Clay),
		Kit.block("Body", V(1.0, 1.4, 0.8), V(0, -0.2, 0), CLAY),
		Kit.ball("Head", 0.95, V(0, 0.95, 0), CLAY),
		Kit.block("ArmL", V(0.3, 0.9, 0.35), V(-0.7, -0.15, 0), CLAY, Enum.Material.SmoothPlastic, V(0, 0, -12)),
		Kit.block("ArmR", V(0.3, 0.9, 0.35), V(0.7, -0.15, 0), CLAY, Enum.Material.SmoothPlastic, V(0, 0, 12)),
		Kit.block("EyeL", V(0.14, 0.14, 0.1), V(-0.2, 1.0, 0.45), P.Dark),
		Kit.block("EyeR", V(0.14, 0.14, 0.1), V(0.2, 1.0, 0.45), P.Dark),
	}
end

-- Common. Pottery shard: two curved-looking fragments with a painted band.
function builders.shard()
	local CLAY = P.Clay
	return {
		Kit.block("PieceA", V(1.6, 1.3, 0.35), V(-0.2, 0, 0), CLAY, Enum.Material.SmoothPlastic, V(0, 0, 14)),
		Kit.block("PieceB", V(1.0, 0.9, 0.35), V(0.9, -0.5, 0.1), P.Dirt, Enum.Material.SmoothPlastic, V(0, 0, -22)),
		Kit.block("Band", V(1.4, 0.22, 0.38), V(-0.2, 0.15, 0), P.Cream, Enum.Material.SmoothPlastic, V(0, 0, 14)),
	}
end

-- Uncommon. Fossil fragment: a spiral shell built from stacked rings, in a rock chunk.
function builders.fossil()
	local BONE = P.Cream
	return {
		Kit.block("Rock", V(2.2, 1.9, 0.7), V(0, 0, -0.2), hex("8A8F96"), Enum.Material.Slate),
		Kit.cyl("Whorl1", "Z", 0.35, 1.7, V(0, 0, 0.2), BONE),
		Kit.cyl("Whorl2", "Z", 0.4, 1.15, V(0, 0, 0.25), P.Sandstone),
		Kit.cyl("Whorl3", "Z", 0.45, 0.6, V(0, 0, 0.3), BONE),
	}
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
