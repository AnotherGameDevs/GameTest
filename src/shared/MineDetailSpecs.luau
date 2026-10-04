-- Part specs for the small remnants that appear on exposed mine faces (see MineStyle.Detail). Local frame of every
-- detail: origin = centre of the 4x4-stud cell face, +Z points OUT of the wall, X/Y lie in the face. Parts are embedded
-- 0.04 studs into the wall so nothing floats. Ambient remnants are LOW (<= 0.14 studs) and tone-on-tone with the layer;
-- "tells" (the visible sign of a REAL reward in that cell) stand proud (0.25+) and use that treasure's own colours, so
-- the two are never confused. Tested in tests/mine_style_test.luau.
local Kit = require(script.Parent.ModelKit)
local Config = require(script.Parent.Config)

local MineDetailSpecs = {}

local V = Vector3.new
local function hex(s: string): Color3
	return Color3.fromHex(s)
end
local P = Config.Palette

local function lay(name: string, size: Vector3, x: number, y: number, color: Color3, mat: Enum.Material?, rotZ: number?)
	-- a block lying on the face: footprint (size.X, size.Y), height size.Z
	return Kit.block(name, size, V(x, y, size.Z / 2 - 0.04), color, mat, V(0, 0, rotZ or 0))
end

local builders = {}

-- Ambient ---------------------------------------------------------------------------------------------------------------
function builders.pebbles() -- soil: two or three small stones
	local a, b = hex("7B6A58"), hex("8C7A66")
	return {
		lay("StoneA", V(0.8, 0.6, 0.16), -0.5, 0.3, a, Enum.Material.Slate, 20),
		lay("StoneB", V(0.5, 0.45, 0.14), 0.45, -0.25, b, Enum.Material.Slate, -15),
		lay("StoneC", V(0.35, 0.3, 0.1), -0.1, -0.7, a, Enum.Material.Slate, 40),
	}
end

function builders.roots() -- shallow soil: short root sections that run into the wall
	local root, dark = hex("6A4A2E"), hex("4E3520")
	return {
		lay("Root", V(2.0, 0.16, 0.14), 0, 0.1, root, Enum.Material.Wood, 12),
		lay("Branch", V(1.0, 0.11, 0.1), 0.55, 0.45, dark, Enum.Material.Wood, 52),
		lay("Twig", V(0.7, 0.09, 0.09), -0.7, -0.25, dark, Enum.Material.Wood, -30),
	}
end

function builders.sherds() -- clay: a cluster of broken pottery, muted so it reads as debris, not treasure
	local a, b, rim = hex("A25F3B"), hex("8E5233"), hex("6E3F28")
	return {
		lay("SherdA", V(0.9, 0.55, 0.12), -0.4, 0.2, a, Enum.Material.Sandstone, 18),
		lay("SherdB", V(0.6, 0.45, 0.12), 0.45, -0.1, b, Enum.Material.Sandstone, -28),
		lay("SherdC", V(0.45, 0.35, 0.1), -0.05, -0.55, a, Enum.Material.Sandstone, 62),
		lay("Rim", V(0.5, 0.1, 0.14), -0.4, 0.48, rim, Enum.Material.Sandstone, 18),
	}
end

function builders.seam() -- stone: a thin mineral seam crossing the face
	local mineral, quartz = hex("7FA3A0"), hex("B7C0C2")
	return {
		lay("Seam", V(3.2, 0.2, 0.08), 0, 0.2, mineral, Enum.Material.Slate, 28),
		lay("Vein", V(1.6, 0.1, 0.1), 0.5, -0.1, quartz, Enum.Material.Slate, 28),
	}
end

function builders.fossil_impression() -- stone: a faint spiral impression (flush, tone-on-tone)
	local c = hex("8C939C")
	local parts = {}
	for i = 0, 9 do
		local th = i * 0.75
		local r = 0.1 * math.exp(0.2 * th)
		parts[#parts + 1] = lay("Whorl" .. i, V(0.18 + r * 0.55, 0.11, 0.07), r * math.cos(th), r * math.sin(th), c, Enum.Material.Slate, math.deg(th) + 90)
	end
	return parts
end

function builders.worked_fragment() -- ruins: a broken, squared stone with a cut groove
	local stone, groove = hex("CDBB92"), hex("8C7650")
	return {
		lay("Block", V(1.0, 0.7, 0.14), -0.1, 0.1, stone, Enum.Material.Limestone, 10),
		lay("Groove", V(0.9, 0.09, 0.16), -0.1, 0.1, groove, Enum.Material.Limestone, 10),
		lay("Chip", V(0.4, 0.3, 0.1), 0.55, -0.35, stone, Enum.Material.Limestone, -25),
	}
end

function builders.carving() -- ruins: a shallow carved panel with a few glyph bars
	local slab, glyph = hex("C2A265"), hex("7D6240")
	local parts = { lay("Panel", V(1.9, 1.0, 0.1), 0, 0, slab, Enum.Material.Limestone, 0) }
	for i = 1, 3 do
		parts[#parts + 1] = lay("Glyph" .. i, V(i == 2 and 1.1 or 0.7, 0.1, 0.13), (i - 2) * 0.1, (i - 2) * 0.28, glyph, Enum.Material.Limestone, 0)
	end
	return parts
end

-- Tells (real rewards; colours match the treasure) -----------------------------------------------------------------------
function builders.tell_coin()
	local gold, rim = hex("B8964A"), hex("8F7330")
	return {
		Kit.cyl("CoinRim", "Z", 0.3, 1.0, V(0, 0, 0.11), rim, Enum.Material.Metal),
		Kit.cyl("CoinFace", "Z", 0.34, 0.78, V(0, 0, 0.13), gold, Enum.Material.Metal),
	}
end

function builders.tell_pottery()
	local fire, band = hex("B5683F"), hex("E3D2B0")
	return {
		lay("PotA", V(1.1, 0.7, 0.3), -0.35, 0.15, fire, Enum.Material.SmoothPlastic, 15),
		lay("PotB", V(0.7, 0.55, 0.28), 0.5, -0.2, fire, Enum.Material.SmoothPlastic, -30),
		lay("PotBand", V(1.1, 0.12, 0.34), -0.35, 0.15, band, Enum.Material.SmoothPlastic, 15),
	}
end

function builders.tell_fossil()
	local bone = hex("D9CFB4")
	local parts = {}
	for i = 0, 9 do
		local th = i * 0.75
		local r = 0.1 * math.exp(0.2 * th)
		parts[#parts + 1] = lay("Whorl" .. i, V(0.22 + r * 0.6, 0.15, 0.32), r * math.cos(th), r * math.sin(th), bone, Enum.Material.SmoothPlastic, math.deg(th) + 90)
	end
	return parts
end

function builders.tell_tablet()
	local sand, glyph = P.Sandstone, hex("8C6B3E")
	return {
		lay("TabletEdge", V(1.5, 1.1, 0.3), 0, 0, sand, Enum.Material.Limestone, 8),
		lay("TabletGlyph", V(0.9, 0.12, 0.34), 0, 0.1, glyph, Enum.Material.Limestone, 8),
	}
end

MineDetailSpecs.Kinds = {}
for kind in pairs(builders) do
	table.insert(MineDetailSpecs.Kinds, kind)
end
table.sort(MineDetailSpecs.Kinds)

function MineDetailSpecs.Has(kind: string): boolean
	return builders[kind] ~= nil
end

-- Specs for one detail, turned by variant*90 degrees about the face normal so repeats do not look identical.
function MineDetailSpecs.Build(kind: string, variant: number)
	local list = builders[kind]()
	if variant ~= 0 then
		return Kit.Transform(list, 1, V(0, 0, 90 * variant))
	end
	return list
end

return MineDetailSpecs
