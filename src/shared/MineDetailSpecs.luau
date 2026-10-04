-- Part specs for the small AMBIENT remnants that appear on exposed mine faces (see MineStyle.Detail). They are plain geology
-- (roots, pebbles, cracks, seams, rubble, mortar lines): this module deliberately does not know about treasures at all.
-- Local frame of every
-- detail: origin = centre of the 4x4-stud cell face, +Z points OUT of the wall, X/Y lie in the face. Parts are embedded
-- 0.04 studs into the wall so nothing floats. Remnants are LOW (<= 0.16 studs), dull and tone-on-tone with the layer.
-- Tested in tests/mine_style_test.luau.
local Kit = require(script.Parent.ModelKit)

local MineDetailSpecs = {}

local V = Vector3.new
local function hex(s: string): Color3
	return Color3.fromHex(s)
end

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

function builders.cracks() -- clay / stone: thin dark cracks crossing the face
	local dark = hex("3E342C")
	return {
		lay("Crack", V(2.8, 0.1, 0.06), 0, 0.2, dark, Enum.Material.Slate, 24),
		lay("Branch", V(1.2, 0.08, 0.06), 0.6, -0.15, dark, Enum.Material.Slate, -38),
	}
end

function builders.seam() -- stone: a thin dull mineral seam crossing the face
	local mineral, vein = hex("6B7773"), hex("979F9E")
	return {
		lay("Seam", V(3.2, 0.2, 0.08), 0, 0.2, mineral, Enum.Material.Slate, 28),
		lay("Vein", V(1.6, 0.1, 0.1), 0.5, -0.1, vein, Enum.Material.Slate, 28),
	}
end

function builders.rubble() -- ruins: a few chunks of broken grey-brown stone (plain debris, no carved shape)
	local a, b = hex("8C7F6C"), hex("746A5C")
	return {
		lay("ChunkA", V(0.9, 0.7, 0.14), -0.3, 0.2, a, Enum.Material.Slate, 14),
		lay("ChunkB", V(0.6, 0.5, 0.12), 0.5, -0.2, b, Enum.Material.Slate, -30),
		lay("ChunkC", V(0.4, 0.35, 0.1), -0.1, -0.7, a, Enum.Material.Slate, 55),
	}
end

function builders.mortar() -- ruins: faint mortar lines of a buried wall (long thin lines, nothing collectible)
	local line = hex("9C8F78")
	return {
		lay("MortarH", V(3.0, 0.1, 0.05), 0, 0.5, line, Enum.Material.Limestone, 0),
		lay("MortarV1", V(0.1, 1.0, 0.05), -0.8, 0, line, Enum.Material.Limestone, 0),
		lay("MortarV2", V(0.1, 1.0, 0.05), 0.9, 0, line, Enum.Material.Limestone, 0),
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
