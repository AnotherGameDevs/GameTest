-- Artifact models. ONE source of truth: these part specs drive the discovery reveal, the carried artifact (world and
-- first-person), the world pickup, the journal preview and the camp shelf. Only the scale (and, for displays, a gentle
-- tilt) differs per use. See docs/ARTIFACT_MODELS.md for the per-artifact brief.
--
-- Style: chunky, hand-made archaeological objects built from deliberate shapes (arcs of tapered segments, stacked
-- courses, layered rims), muted materials and restrained wear. Nothing relies on glow: no Neon anywhere, gems are glass.
-- Rarity is shown by the reveal outline/light colour, never by the material.
-- Frame of every model: +Y up, front faces +Z, origin near the centre, roughly 2-3 studs across.
-- Mesh-dependent parts (none shipped): see the MESH NOTES in docs/ARTIFACT_MODELS.md.
local Kit = require(script.Parent.ModelKit)
local Config = require(script.Parent.Config)

local TreasureModels = {}

local V = Vector3.new
local function hex(s: string): Color3
	return Color3.fromHex(s)
end
local SP, GL = Enum.Material.SmoothPlastic, Enum.Material.Glass

-- Muted archaeological palette
local TERRA, TERRA_DARK, TERRA_LIGHT, CLAY_DEEP = hex("B5683F"), hex("8E4F30"), hex("C98A5E"), hex("5B3A26")
local PAINT, CREAM = hex("7A3322"), hex("E3D2B0")
local BRONZE, BRONZE_DARK, BRONZE_LIGHT, PATINA = hex("A9744A"), hex("7D5232"), hex("BC8858"), hex("5E8374")
local GOLD, GOLD_DARK = hex("C9A24B"), hex("9A7A32")
local BONE, BONE_DARK = hex("D8CDB0"), hex("B9A57E")
local SLATE, SLATE_DARK, SLATE_LIGHT = hex("6E7580"), hex("565D68"), hex("7B838E")
local SAND, SAND_DARK, CARVE = hex("C9AE7C"), hex("A98E5E"), hex("7D6240")
local LAPIS, TEAL = hex("3A72AE"), hex("3F8F88")

local builders = {}

-- Helpers ------------------------------------------------------------------------------------------------------------
-- A block whose X axis runs along the tangent of a circle at angle `deg` (0 = +X, 90 = +Y), centred on the arc.
local function arcBlock(name: string, cx: number, cy: number, radius: number, deg: number, size: Vector3, z: number, color: Color3, mat: Enum.Material?)
	local a = math.rad(deg)
	return Kit.block(name, size, V(cx + radius * math.cos(a), cy + radius * math.sin(a), z), color, mat or SP, V(0, 0, deg + 90))
end

local function withTransparency(spec, t: number)
	spec.Transparency = t
	return spec
end

-- 1. Old coin (Common): thin, round, defined rim, raised sun emblem on the front. -------------------------------------
function builders.coin()
	local parts = {
		Kit.cyl("Rim", "Z", 0.26, 2.3, V(0, 0, 0), GOLD_DARK, Enum.Material.Metal),
		Kit.cyl("Face", "Z", 0.3, 1.9, V(0, 0, 0.02), GOLD, Enum.Material.Metal),
		Kit.cyl("EmblemDisc", "Z", 0.38, 0.62, V(0, 0, 0.04), GOLD_DARK, Enum.Material.Metal),
	}
	for i = 0, 3 do -- four rays through the centre = an eight-point sunburst
		table.insert(parts, Kit.block("Ray" .. i, V(1.45, 0.13, 0.38), V(0, 0, 0.04), GOLD_DARK, Enum.Material.Metal, V(0, 0, i * 45)))
	end
	return parts
end

-- 2. Bronze ring (Uncommon): an open circular band built from 12 chunky segments, thickened at the top with a raised
-- diamond, bronze with patina on a few segments. The centre is open (see tests). -----------------------------------------
function builders.ring()
	local parts = {}
	local R = 0.95
	for i = 0, 11 do
		local deg = i * 30
		if deg ~= 90 then -- the top is the bezel
			local color = (i % 4 == 1) and BRONZE_DARK or BRONZE
			if i == 4 or i == 9 then color = PATINA end
			table.insert(parts, arcBlock("Band" .. i, 0, 0, R, deg, V(0.64, 0.34, 0.5), 0, color, Enum.Material.Metal))
		end
	end
	table.insert(parts, Kit.block("Bezel", V(0.95, 0.66, 0.62), V(0, R + 0.02, 0), BRONZE_LIGHT, Enum.Material.Metal))
	table.insert(parts, Kit.block("Emblem", V(0.4, 0.4, 0.14), V(0, R + 0.02, 0.34), BRONZE_DARK, Enum.Material.Metal, V(0, 0, 45)))
	table.insert(parts, Kit.block("EmblemCut", V(0.14, 0.14, 0.17), V(0, R + 0.02, 0.36), PATINA, Enum.Material.Metal, V(0, 0, 45)))
	return parts
end

-- 3. Clay figurine (Uncommon): hand-modelled terracotta figure on a base. ---------------------------------------------
function builders.figurine()
	return {
		Kit.block("Base", V(1.55, 0.3, 1.15), V(0, -1.5, 0), CLAY_DEEP),
		Kit.block("LowerTorso", V(1.1, 0.85, 0.72), V(0, -0.85, 0), TERRA),
		Kit.block("Belt", V(0.98, 0.1, 0.66), V(0, -0.38, 0.02), TERRA_DARK),
		Kit.block("UpperTorso", V(0.88, 0.75, 0.62), V(0, -0.0, 0), TERRA),
		Kit.block("Shoulders", V(1.18, 0.26, 0.58), V(0, 0.38, 0), TERRA_DARK),
		Kit.cyl("Neck", "Y", 0.32, 0.36, V(0, 0.68, 0), TERRA),
		Kit.ellipsoid("Head", V(0.86, 1.0, 0.82), V(0, 1.2, 0), TERRA_LIGHT),
		Kit.block("Nose", V(0.14, 0.3, 0.2), V(0, 1.12, 0.43), TERRA_LIGHT),
		Kit.block("Brow", V(0.62, 0.07, 0.1), V(0, 1.4, 0.38), TERRA_DARK),
		Kit.block("EyeL", V(0.15, 0.06, 0.05), V(-0.2, 1.28, 0.4), CLAY_DEEP),
		Kit.block("EyeR", V(0.15, 0.06, 0.05), V(0.2, 1.28, 0.4), CLAY_DEEP),
		Kit.block("Mouth", V(0.3, 0.05, 0.05), V(0, 0.88, 0.4), CLAY_DEEP),
		-- distinct arms: the left hangs, the right is bent up toward the chest
		Kit.block("ArmL", V(0.28, 0.9, 0.3), V(-0.78, -0.05, 0.02), TERRA, SP, V(0, 0, 6)),
		Kit.ball("HandL", 0.3, V(-0.84, -0.55, 0.02), TERRA),
		Kit.block("UpperArmR", V(0.28, 0.55, 0.3), V(0.8, 0.12, 0.02), TERRA, SP, V(0, 0, -10)),
		Kit.block("ForearmR", V(0.26, 0.55, 0.28), V(0.66, -0.22, 0.2), TERRA, SP, V(0, 0, 55)),
		Kit.ball("HandR", 0.28, V(0.4, -0.3, 0.32), TERRA),
		-- wear: one chipped corner on the base, showing the paler fired clay beneath
		Kit.block("Chip", V(0.38, 0.22, 0.3), V(-0.62, -1.44, 0.42), TERRA_LIGHT, SP, V(0, 0, 20)),
		Kit.block("IncisedBelt", V(0.8, 0.04, 0.04), V(0, -0.62, 0.37), CLAY_DEEP),
	}
end

-- 4. Fossil fragment (Uncommon): a broken slab of cool rock with an ammonite spiral standing out of its face. ------------
function builders.fossil()
	local parts = {
		Kit.block("Slab", V(2.5, 2.0, 0.6), V(0, 0, -0.1), SLATE, Enum.Material.Slate),
		Kit.block("ChunkTop", V(1.3, 0.85, 0.55), V(-0.75, 0.98, -0.08), SLATE_LIGHT, Enum.Material.Slate, V(0, 0, 9)),
		Kit.block("ChunkRight", V(0.9, 1.3, 0.52), V(1.18, -0.3, -0.1), SLATE_DARK, Enum.Material.Slate, V(0, 0, -11)),
		Kit.block("ChipA", V(0.5, 0.35, 0.5), V(-1.15, -0.85, -0.05), SLATE_DARK, Enum.Material.Slate, V(0, 0, 32)),
		Kit.block("ChipB", V(0.4, 0.3, 0.5), V(0.5, -1.05, -0.05), SLATE_LIGHT, Enum.Material.Slate, V(0, 0, -20)),
	}
	-- the ammonite: a logarithmic spiral of tapered shell segments with a rib across each one
	local cx, cy = -0.1, 0.05
	for i = 0, 11 do
		local th = i * 0.9
		local r = 0.12 * math.exp(0.2 * th)
		local w = 0.12 + 0.34 * r
		local deg = math.deg(th)
		local px, py = cx + r * math.cos(th), cy + r * math.sin(th)
		table.insert(parts, Kit.block("Shell" .. i, V(r * 0.95 + 0.14, w, 0.2), V(px, py, 0.28), BONE, SP, V(0, 0, deg + 90)))
		table.insert(parts, Kit.block("Rib" .. i, V(0.06, w * 0.9, 0.24), V(px, py, 0.29), BONE_DARK, SP, V(0, 0, deg + 90 + 90)))
	end
	return parts
end

-- 5. Ancient necklace (Rare): a beaded and linked loop with a pendant in a shaped gold setting, on a small neutral stand. -
function builders.necklace()
	local parts = {
		Kit.cyl("StandBase", "Y", 0.16, 1.6, V(0, -2.0, -0.2), SLATE_DARK, Enum.Material.Slate),
		Kit.cyl("StandColumn", "Y", 1.0, 0.5, V(0, -1.4, -0.2), SLATE, Enum.Material.Slate),
		Kit.ellipsoid("Bust", V(1.9, 2.1, 0.55), V(0, 0.2, -0.3), hex("8A7F70"), Enum.Material.Fabric),
	}
	local R, cy, z = 1.0, 0.35, 0.2
	local n = 0
	for deg = 195, 525, 22 do -- sweep over the top, leaving the bottom open for the pendant
		n += 1
		local a = math.rad(deg)
		local x, y = R * math.cos(a), cy + R * math.sin(a)
		table.insert(parts, Kit.ball("Bead" .. n, 0.4, V(x, y, z), (n % 3 == 0) and GOLD_DARK or GOLD, Enum.Material.Metal))
		local m = math.rad(deg + 11)
		table.insert(parts, Kit.block("Link" .. n, V(0.32, 0.12, 0.12), V(R * math.cos(m), cy + R * math.sin(m), z), GOLD_DARK, Enum.Material.Metal, V(0, 0, deg + 11 + 90)))
	end
	-- drop links from both chain ends to the pendant
	table.insert(parts, Kit.block("DropL", V(0.14, 0.5, 0.14), V(-0.62, -0.62, z), GOLD_DARK, Enum.Material.Metal, V(0, 0, -30)))
	table.insert(parts, Kit.block("DropR", V(0.14, 0.5, 0.14), V(0.62, -0.62, z), GOLD_DARK, Enum.Material.Metal, V(0, 0, 30)))
	table.insert(parts, Kit.block("Bail", V(0.5, 0.2, 0.2), V(0, -0.82, z), GOLD, Enum.Material.Metal))
	table.insert(parts, Kit.block("Setting", V(0.95, 0.95, 0.24), V(0, -1.3, z), GOLD, Enum.Material.Metal, V(0, 0, 45)))
	table.insert(parts, Kit.block("SettingRim", V(0.72, 0.72, 0.3), V(0, -1.3, z), GOLD_DARK, Enum.Material.Metal, V(0, 0, 45)))
	table.insert(parts, withTransparency(Kit.block("InsetStone", V(0.5, 0.5, 0.34), V(0, -1.3, z), LAPIS, GL, V(0, 0, 45)), 0.1))
	return parts
end

-- 6. Pottery shard (Common): a curved piece of vessel wall with visible thickness, different inside and outside, a painted
-- band and dots, with uneven, deliberately broken edges. ----------------------------------------------------------------
function builders.shard()
	local parts = {}
	local R = 1.6
	local heights = { 0.9, 1.3, 1.1, 1.7, 1.4, 1.9, 1.2, 1.0, 0.7 } -- uneven, broken top edge
	local n = #heights
	for i, h in ipairs(heights) do
		local phi = -56 + (i - 1) * 14
		local a = math.rad(phi)
		local x, z = R * math.sin(a), R * math.cos(a) - R
		local tilt = (i == 1 or i == n) and 9 or 0 -- the two end pieces are cut at a slant
		table.insert(parts, Kit.block("Outer" .. i, V(0.5, h, 0.2), V(x + math.sin(a) * 0.07, 0, z + math.cos(a) * 0.07), TERRA, SP, V(0, phi, tilt)))
		table.insert(parts, Kit.block("Inner" .. i, V(0.5, h * 0.97, 0.14), V(x - math.sin(a) * 0.1, -0.01, z - math.cos(a) * 0.1), CLAY_DEEP, SP, V(0, phi, tilt)))
	end
	-- painted band + dots on the outer face
	for i = 2, n - 1 do
		local phi = -56 + (i - 1) * 14
		local a = math.rad(phi)
		local x, z = (R + 0.2) * math.sin(a), (R + 0.2) * math.cos(a) - R
		table.insert(parts, Kit.block("Band" .. i, V(0.5, 0.17, 0.07), V(x, 0.18, z), PAINT, SP, V(0, phi, 0)))
		table.insert(parts, Kit.block("Dot" .. i, V(0.12, 0.12, 0.08), V(x, -0.22, z), CREAM, SP, V(0, phi, 0)))
	end
	return parts
end

-- 7. Cut gemstone (Rare): a stepped brilliant-cut in glass (no glow). -----------------------------------------------------
function builders.gem()
	local crown, mid, deep, tbl = hex("7FBBD2"), hex("5FA3BF"), hex("3F7E99"), hex("B7DCE8")
	local function layer(name: string, size: number, h: number, y: number, color: Color3)
		return Kit.block(name, V(size, h, size), V(0, y, 0), color, GL, V(0, 45, 0))
	end
	return {
		layer("Girdle", 1.9, 0.25, 0, mid),
		layer("Crown1", 1.55, 0.3, 0.27, crown),
		layer("Crown2", 1.1, 0.3, 0.55, crown),
		layer("Table", 0.65, 0.2, 0.78, tbl),
		layer("Pav1", 1.55, 0.3, -0.27, mid),
		layer("Pav2", 1.1, 0.3, -0.55, deep),
		layer("Pav3", 0.7, 0.3, -0.83, deep),
		layer("Culet", 0.3, 0.2, -1.05, deep),
	}
end

-- 8. Ruin tablet (Rare): a slab of worked sandstone with a border, four rows of carved glyphs, a chipped corner and a crack. -
function builders.tablet()
	local parts = {
		Kit.block("Slab", V(2.0, 2.6, 0.5), V(0, 0, 0), SAND, Enum.Material.Sandstone),
		Kit.block("BorderTop", V(1.7, 0.1, 0.56), V(0, 1.12, 0), SAND_DARK, Enum.Material.Sandstone),
		Kit.block("BorderBottom", V(1.7, 0.1, 0.56), V(0, -1.12, 0), SAND_DARK, Enum.Material.Sandstone),
		Kit.block("BorderL", V(0.1, 2.34, 0.56), V(-0.85, 0, 0), SAND_DARK, Enum.Material.Sandstone),
		Kit.block("BorderR", V(0.1, 2.34, 0.56), V(0.85, 0, 0), SAND_DARK, Enum.Material.Sandstone),
		Kit.block("Chip", V(0.7, 0.7, 0.54), V(0.92, 1.2, 0), SLATE_DARK, Enum.Material.Slate, V(0, 0, 45)),
		Kit.block("Crack", V(0.07, 0.9, 0.56), V(-0.3, -0.45, 0), CARVE, SP, V(0, 0, 14)),
	}
	for row = 1, 4 do
		for col = 1, 3 do
			local wide = (row + col) % 2 == 0
			table.insert(parts, Kit.block(("Glyph%d_%d"):format(row, col), V(wide and 0.36 or 0.2, 0.2, 0.58), V((col - 2) * 0.48, 0.85 - (row - 1) * 0.5, 0), CARVE, SP))
		end
	end
	return parts
end

-- 9. Fossil claw (Epic): a curved bone claw of six tapering segments with knuckle ridges and a dark tip, on a rock base. ----
function builders.claw()
	local parts = {
		Kit.block("Base", V(2.3, 0.5, 1.3), V(0.2, -1.6, 0), SLATE, Enum.Material.Slate, V(0, 0, 3)),
		Kit.block("BaseChip", V(0.7, 0.35, 0.9), V(-0.7, -1.38, 0.1), SLATE_LIGHT, Enum.Material.Slate, V(0, 0, 18)),
	}
	local cx, cy, R = -1.0, -1.15, 2.25
	for i = 0, 5 do
		local deg = 6 + i * 14
		local t = i / 5
		local w = 1.0 - 0.78 * t -- radial width tapers
		local d = 0.85 - 0.55 * t -- thickness tapers
		local color = (i == 5) and hex("5A4A33") or ((i % 2 == 0) and BONE or BONE_DARK)
		table.insert(parts, arcBlock("Seg" .. i, cx, cy, R, deg, V(0.78, w, d), 0, color))
		if i < 5 then -- knuckle ridge at the joint
			table.insert(parts, arcBlock("Ridge" .. i, cx, cy, R, deg + 7, V(0.1, w + 0.08, d + 0.08), 0, BONE_DARK))
		end
	end
	return parts
end

-- 10. Golden scarab (Epic): beetle with a ridged shell, head, six legs, aged gold with lapis eyes and a teal glass gem. ----
function builders.scarab()
	local parts = {
		Kit.ellipsoid("Shell", V(2.2, 1.3, 2.8), V(0, 0, 0.1), GOLD, Enum.Material.Metal),
		Kit.ellipsoid("Head", V(1.3, 0.8, 0.95), V(0, -0.05, -1.6), GOLD_DARK, Enum.Material.Metal),
		Kit.block("WingSplit", V(0.12, 0.14, 2.2), V(0, 0.64, 0.25), GOLD_DARK, Enum.Material.Metal),
		Kit.ball("SunGem", 0.6, V(0, 0.62, -0.55), TEAL, GL),
		Kit.ball("EyeL", 0.3, V(-0.36, 0.08, -2.0), LAPIS, GL),
		Kit.ball("EyeR", 0.3, V(0.36, 0.08, -2.0), LAPIS, GL),
	}
	for i, z in ipairs({ -0.7, 0.25, 1.15 }) do
		for _, side in ipairs({ -1, 1 }) do
			table.insert(parts, Kit.block(("Leg%d_%d"):format(i, side), V(0.9, 0.28, 0.34),
				V(side * 1.35, -0.45, z), GOLD_DARK, Enum.Material.Metal, V(0, side * (20 - i * 12), side * -12)))
		end
	end
	return parts
end

-- 11. Sun pharaoh mask (Legendary): aged-gold funerary mask with a striped lapis headdress, inlaid eyes, nose, beard. ------
function builders.mask()
	return {
		Kit.block("Face", V(1.7, 2.2, 0.8), V(0, 0, 0), GOLD, Enum.Material.Metal),
		Kit.block("HeadCloth", V(2.5, 1.0, 1.1), V(0, 1.2, -0.1), GOLD_DARK, Enum.Material.Metal),
		Kit.block("SideL", V(0.55, 2.4, 0.9), V(-1.4, -0.1, -0.1), GOLD_DARK, Enum.Material.Metal),
		Kit.block("SideR", V(0.55, 2.4, 0.9), V(1.4, -0.1, -0.1), GOLD_DARK, Enum.Material.Metal),
		Kit.block("StripeL", V(0.2, 2.0, 0.92), V(-1.4, -0.1, -0.1), LAPIS, SP),
		Kit.block("StripeR", V(0.2, 2.0, 0.92), V(1.4, -0.1, -0.1), LAPIS, SP),
		Kit.block("Brow", V(1.5, 0.22, 0.2), V(0, 0.45, 0.42), LAPIS, SP),
		Kit.block("EyeL", V(0.45, 0.28, 0.2), V(-0.42, 0.2, 0.42), CREAM, SP),
		Kit.block("EyeR", V(0.45, 0.28, 0.2), V(0.42, 0.2, 0.42), CREAM, SP),
		Kit.block("PupilL", V(0.16, 0.2, 0.22), V(-0.42, 0.2, 0.43), LAPIS, SP),
		Kit.block("PupilR", V(0.16, 0.2, 0.22), V(0.42, 0.2, 0.43), LAPIS, SP),
		Kit.block("Nose", V(0.3, 0.8, 0.3), V(0, -0.2, 0.5), GOLD_DARK, Enum.Material.Metal),
		Kit.block("Mouth", V(0.7, 0.14, 0.2), V(0, -0.78, 0.42), GOLD_DARK, Enum.Material.Metal),
		Kit.block("Beard", V(0.5, 0.9, 0.4), V(0, -1.5, 0.2), LAPIS, SP),
		Kit.ball("CrownGem", 0.5, V(0, 1.55, 0.45), TEAL, GL),
	}
end

-- Generic stand-ins for any future treasure without a model (all current treasures have one). ----------------------------
local function genericSpecs(def)
	return { Kit.block("Body", V(2.2, 1.6, 1.8), V(0, 0, 0), def.Color, SP) }
end

-- Display --------------------------------------------------------------------------------------------------------------
-- Pitch (degrees about X, applied for the journal and the camp shelf only) that turns an object toward a viewer standing in
-- front of and a little above it: + tips the top toward the viewer, - tips the front face upward.
TreasureModels.DisplayPitch = {
	bronze_ring = -28, old_coin = -22, cut_gemstone = 18, golden_scarab = 32, ruin_tablet = -8,
	pottery_shard = -6, fossil_fragment = -14, fossil_claw = -4,
}
-- Extra yaw (degrees) so asymmetric objects show their best side.
TreasureModels.DisplayYaw = { pottery_shard = -18, fossil_claw = -12 }

function TreasureModels.DisplayRotation(treasureId: string): CFrame
	return CFrame.Angles(math.rad(TreasureModels.DisplayPitch[treasureId] or 0), math.rad(TreasureModels.DisplayYaw[treasureId] or 0), 0)
end

-- Artifacts whose required silhouette needs an authored mesh (parts cannot do it cleanly). Until a mesh set is configured in
-- Config.MeshAssets their model is the primitive FALLBACK below and counts as UNFINISHED.
TreasureModels.MeshRequired = { "pottery_shard", "cut_gemstone", "fossil_fragment", "clay_figurine", "fossil_claw", "golden_scarab", "sun_mask" }

-- "mesh" (authored mesh in use), "unfinished" (needs a mesh, primitive fallback shown) or "parts" (primitives are the final art).
function TreasureModels.Status(treasureId: string): string
	if Config.MeshAssets[treasureId] and #Config.MeshAssets[treasureId] > 0 then
		return "mesh"
	end
	if table.find(TreasureModels.MeshRequired, treasureId) then
		return "unfinished"
	end
	return "parts"
end

local function meshSpecs(entries)
	local out = {}
	for _, e in ipairs(entries) do
		table.insert(out, {
			Name = e.Name, Shape = "Mesh", MeshId = e.MeshId, MeshSize = e.Size, Size = e.Size, Offset = CFrame.identity,
			Color = Color3.fromHex(e.Color), Material = Enum.Material[e.Material or "SmoothPlastic"],
		})
	end
	return out
end

-- Part specs (origin-centred) for a treasure id. `def` is the Defs entry (passed in to avoid a require cycle). The same specs
-- (mesh set when configured, else the primitive fallback) feed reveals, carrying, journal, shelf and buried tells.
function TreasureModels.Specs(treasureId: string, def)
	local assets = Config.MeshAssets[treasureId]
	if assets and #assets > 0 then
		return meshSpecs(assets)
	end
	local builder = def.Model and builders[def.Model]
	if builder then
		return builder()
	end
	return genericSpecs(def)
end

-- Axis-aligned bounds of a spec list (rotation-aware): returns min and max corners.
function TreasureModels.Bounds(specs): (Vector3, Vector3)
	local lo, hi = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
	for _, s in ipairs(specs) do
		local r = s.Offset.RightVector
		local u = s.Offset.UpVector
		local b = s.Offset.LookVector
		local hx, hy, hz = s.Size.X / 2, s.Size.Y / 2, s.Size.Z / 2
		local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(b.X) * hz
		local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(b.Y) * hz
		local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(b.Z) * hz
		local p = s.Offset.Position
		lo = V(math.min(lo.X, p.X - ex), math.min(lo.Y, p.Y - ey), math.min(lo.Z, p.Z - ez))
		hi = V(math.max(hi.X, p.X + ex), math.max(hi.Y, p.Y + ey), math.max(hi.Z, p.Z + ez))
	end
	return lo, hi
end

-- Largest side of the model's part bounds, in studs.
function TreasureModels.MaxExtent(specs): number
	local lo, hi = TreasureModels.Bounds(specs)
	return math.max(hi.X - lo.X, hi.Y - lo.Y, hi.Z - lo.Z)
end

-- Anchored, ready-to-animate Model (PrimaryPart "Root" at the origin). Always succeeds.
function TreasureModels.BuildAny(treasureId: string, def): Model
	return Kit.BuildModel(TreasureModels.Specs(treasureId, def), treasureId)
end

-- The SAME model for a display (journal / shelf): scaled so its largest side equals `targetSize` studs, so every artifact
-- has a consistent size relative to its pedestal. Callers pose it (see DisplayRotation).
function TreasureModels.BuildDisplay(treasureId: string, def, targetSize: number): Model
	local specs = TreasureModels.Specs(treasureId, def)
	local scale = targetSize / math.max(TreasureModels.MaxExtent(specs), 0.1)
	return Kit.BuildModel(Kit.Transform(specs, scale, nil), treasureId)
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
