-- Chunky backpack models for the shop (same Kit/palette as tools and artifacts). Five packs, each visibly bigger and
-- better equipped than the last, so the progression reads without reading the capacity number.
local Kit = require(script.Parent.ModelKit)

local PackModels = {}

local V = Vector3.new
local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local LEATHER, LEATHER_DARK, CANVAS, CANVAS_DARK = hex("A8703E"), hex("6E4527"), hex("7A8C5C"), hex("56673E")
local STEEL, ORANGE, GOLD = hex("8E98A3"), hex("E5602B"), hex("F5B942")
local STRAP = hex("3A2A1C")

local builders = {}

local function strap(name: string, x: number, h: number, z: number)
	return Kit.block(name, V(0.3, h, 0.2), V(x, 0, z), STRAP)
end

function builders.pack_pouch()
	return {
		Kit.block("Body", V(2.4, 2.4, 1.4), V(0, 0, 0), LEATHER),
		Kit.block("Flap", V(2.6, 0.9, 1.6), V(0, 1.2, 0), LEATHER_DARK),
		Kit.block("Buckle", V(0.5, 0.5, 0.2), V(0, 0.75, 0.85), GOLD),
		strap("StrapL", -0.7, 2.6, -0.8), strap("StrapR", 0.7, 2.6, -0.8),
	}
end

function builders.pack_satchel()
	return {
		Kit.block("Body", V(3.4, 2.4, 1.3), V(0, -0.2, 0), CANVAS),
		Kit.block("Flap", V(3.6, 1.2, 1.5), V(0, 1.2, 0), CANVAS_DARK),
		Kit.block("Buckle", V(0.6, 0.6, 0.2), V(0, 0.8, 0.8), GOLD),
		Kit.block("PocketL", V(1.0, 1.1, 0.4), V(-1.0, -0.8, 0.8), CANVAS_DARK),
		Kit.block("PocketR", V(1.0, 1.1, 0.4), V(1.0, -0.8, 0.8), CANVAS_DARK),
		Kit.block("Strap", V(4.2, 0.35, 0.2), V(0, 0.6, -0.8), STRAP, Enum.Material.SmoothPlastic, V(0, 0, 18)),
	}
end

function builders.pack_field()
	return {
		Kit.block("Body", V(3.0, 3.8, 1.8), V(0, 0, 0), CANVAS),
		Kit.block("Lid", V(3.2, 1.0, 2.0), V(0, 2.2, 0), CANVAS_DARK),
		Kit.block("PocketL", V(0.9, 1.7, 0.7), V(-1.1, -0.9, 1.1), CANVAS_DARK),
		Kit.block("PocketR", V(0.9, 1.7, 0.7), V(1.1, -0.9, 1.1), CANVAS_DARK),
		Kit.block("Bedroll", V(3.2, 0.9, 0.9), V(0, -2.4, 0.1), LEATHER, Enum.Material.SmoothPlastic),
		Kit.block("BuckleL", V(0.4, 0.4, 0.2), V(-0.7, 1.7, 1.1), GOLD),
		Kit.block("BuckleR", V(0.4, 0.4, 0.2), V(0.7, 1.7, 1.1), GOLD),
		strap("StrapL", -0.9, 3.8, -1.0), strap("StrapR", 0.9, 3.8, -1.0),
	}
end

function builders.pack_mining()
	return {
		Kit.block("Frame", V(3.6, 4.6, 0.5), V(0, 0, -0.9), STEEL, Enum.Material.Metal),
		Kit.block("Body", V(3.2, 3.6, 1.8), V(0, 0.2, 0.2), LEATHER_DARK),
		Kit.block("Lid", V(3.4, 1.0, 2.0), V(0, 2.5, 0.2), LEATHER),
		Kit.block("Panel", V(2.4, 1.4, 0.3), V(0, -0.3, 1.2), ORANGE),
		Kit.block("PocketL", V(0.8, 1.6, 0.6), V(-1.35, -1.2, 1.1), LEATHER),
		Kit.block("PocketR", V(0.8, 1.6, 0.6), V(1.35, -1.2, 1.1), LEATHER),
		Kit.block("LampBody", V(0.6, 0.6, 0.6), V(0, 3.2, 0.5), STEEL, Enum.Material.Metal),
		Kit.ball("Lamp", 0.5, V(0, 3.2, 0.9), GOLD, Enum.Material.Neon),
		Kit.block("Pick", V(0.2, 2.6, 0.2), V(1.9, 0.4, 0.3), hex("7A5230")),
		strap("StrapL", -1.0, 4.2, -1.3), strap("StrapR", 1.0, 4.2, -1.3),
	}
end

function builders.pack_expedition()
	return {
		Kit.block("Frame", V(4.2, 5.6, 0.6), V(0, 0, -1.1), STEEL, Enum.Material.Metal),
		Kit.block("Body", V(3.8, 4.4, 2.2), V(0, 0.3, 0.2), ORANGE),
		Kit.block("Lid", V(4.0, 1.2, 2.4), V(0, 3.1, 0.2), hex("B84519")),
		Kit.block("PocketL", V(1.1, 2.0, 0.8), V(-1.6, -1.2, 1.4), hex("B84519")),
		Kit.block("PocketR", V(1.1, 2.0, 0.8), V(1.6, -1.2, 1.4), hex("B84519")),
		Kit.block("Panel", V(2.4, 1.6, 0.3), V(0, 0.2, 1.4), STEEL, Enum.Material.Metal),
		Kit.cyl("Bedroll", "X", 4.4, 1.3, V(0, -3.3, 0.2), CANVAS),
		Kit.cyl("RopeCoil", "Z", 0.6, 1.4, V(0, 2.0, 1.6), hex("D8B678")),
		Kit.block("LampBody", V(0.7, 0.7, 0.7), V(0, 4.0, 0.5), STEEL, Enum.Material.Metal),
		Kit.ball("Lamp", 0.6, V(0, 4.0, 0.95), GOLD, Enum.Material.Neon),
		Kit.block("Flag", V(0.2, 1.6, 0.2), V(-1.7, 3.9, -0.4), STEEL, Enum.Material.Metal),
		Kit.block("FlagCloth", V(1.0, 0.7, 0.1), V(-1.2, 4.4, -0.4), GOLD),
		strap("StrapL", -1.1, 5.0, -1.4), strap("StrapR", 1.1, 5.0, -1.4),
	}
end

function PackModels.Has(id: string?): boolean
	return id ~= nil and builders[id] ~= nil
end

-- Anchored preview/FX model (PrimaryPart "Root" at the origin).
function PackModels.BuildPreview(id: string): Model
	return Kit.BuildModel(builders[id](), id)
end

return PackModels
