-- Surroundings: broad, low landforms and a few layered rocky outcrops OUTSIDE the mine, shaped as large coherent masses
-- (stepped sandstone terraces) rather than scattered rocks. Everything here is outside the grid, the elevator route
-- and the playable approaches; the map boundary (invisible walls at +-ext) is unchanged. A far ground plane and
-- distant mesas continue the horizon beyond the boundary so it never reads as a flat edge.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.WorldKit)

local C = Kit.Color
local V = Vector3.new

local WorldLandscape = {}

-- A stepped mesa: `tiers` boxes, each smaller than the one below, in darker->lighter rock bands with a sand cap.
-- cx, cz = centre; w, d = footprint of the lowest tier; heights = per-tier heights.
local function mesa(parent: Instance, name: string, cx: number, cz: number, w: number, d: number, heights: { number }, solid: boolean)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	local y = 0
	local colors = { C.RockDark, C.Rock, C.RockTan }
	for i, h in ipairs(heights) do
		local shrink = 0.74 ^ (i - 1)
		local ox = (i - 1) * 0.06 * w * (i % 2 == 0 and 1 or -1) -- gentle asymmetry, deterministic
		local p = Kit.box(folder, ("Tier%d"):format(i), V(w * shrink, h, d * shrink), V(cx + ox, y + h / 2 - 1, cz),
			colors[math.min(i, #colors)], Enum.Material.Sandstone)
		if not solid then
			Kit.deco(p)
		end
		-- a thin contrasting band where tiers meet reads as strata
		local band = Kit.box(folder, "Band", V(w * shrink + 0.6, 0.7, d * shrink + 0.6), V(cx + ox, y + h - 0.35, cz), C.RockDark, Enum.Material.Sandstone)
		if not solid then
			Kit.deco(band)
		end
		y += h
	end
	local top = heights[#heights]
	local shrink = 0.74 ^ #heights
	local cap = Kit.box(folder, "Cap", V(w * shrink, 1.2, d * shrink), V(cx, y + 0.1, cz), C.RockCap, Enum.Material.Sand)
	if not solid then
		Kit.deco(cap)
	end
	_ = top
end

-- A broad low dune: two overlapping terraces of sand.
local function dune(parent: Instance, name: string, cx: number, cz: number, w: number, d: number, h: number)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	Kit.box(folder, "Base", V(w, h, d), V(cx, h / 2 - 0.5, cz), C.Sand, Enum.Material.Sand)
	Kit.box(folder, "Crest", V(w * 0.6, h, d * 0.62), V(cx + w * 0.05, h * 1.5 - 0.5, cz), Color3.fromHex("E3C592"), Enum.Material.Sand)
end

-- Sparse dry scrub and small rocks, concentrated at the base of a landform.
local function scrub(parent: Instance, rng: Random, cx: number, cz: number, spreadX: number, spreadZ: number, count: number)
	for i = 1, count do
		local x = cx + (rng:NextNumber() - 0.5) * spreadX
		local z = cz + (rng:NextNumber() - 0.5) * spreadZ
		if rng:NextNumber() < 0.6 then
			local s = 1.4 + rng:NextNumber() * 1.2
			local bush = Kit.box(parent, "Scrub", V(s * 1.4, s * 0.8, s * 1.4), V(x, s * 0.3, z), C.Scrub, Enum.Material.Grass)
			Kit.deco(bush)
			local tuft = Kit.box(parent, "ScrubTuft", V(0.3, s * 1.2, 0.3), V(x, s * 0.8, z), Color3.fromHex("A5945A"), Enum.Material.Grass)
			Kit.deco(tuft)
		else
			local r = 0.8 + rng:NextNumber() * 1.4
			Kit.box(parent, "Rock", V(r * 1.6, r, r * 1.3), V(x, r * 0.4, z), C.Stone, Enum.Material.Slate)
		end
	end
end

function WorldLandscape.Build(world: Folder)
	local land = Instance.new("Folder")
	land.Name = "Landscape"
	land.Parent = world
	local ext = 170 -- map boundary (the invisible walls are built by WorldBuilder at +-ext)

	-- Distant ground + mesas beyond the boundary: decoration only (non-solid, not raycast).
	Kit.deco(Kit.box(land, "FarGround", V(1400, 2, 1400), V(0, -1.1, 0), C.Sand, Enum.Material.Sand))
	local far = Instance.new("Folder")
	far.Name = "FarMesas"
	far.Parent = land
	mesa(far, "FarNW", -300, -330, 190, 120, { 26, 22, 16 }, false)
	mesa(far, "FarN", 70, -360, 240, 130, { 30, 24, 18 }, false)
	mesa(far, "FarNE", 330, -250, 170, 140, { 24, 20, 14 }, false)
	mesa(far, "FarE", 380, 40, 150, 160, { 18, 16, 10 }, false)
	mesa(far, "FarW", -380, 20, 160, 150, { 20, 16, 12 }, false)
	mesa(far, "FarSE", 300, 300, 150, 100, { 12, 10 }, false)
	mesa(far, "FarSW", -310, 290, 150, 100, { 12, 10 }, false)

	-- Near landforms (solid, inside the boundary). The south-centre is deliberately left open: that is the way in.
	mesa(land, "NorthMesaWest", -70, -138, 100, 56, { 16, 13, 9 }, true)
	mesa(land, "NorthMesaEast", 52, -146, 120, 62, { 18, 14, 10 }, true)
	mesa(land, "NorthRidgeFar", 142, -122, 54, 52, { 24, 18, 12 }, true)
	mesa(land, "WestOutcrop", -142, -34, 62, 96, { 14, 11, 8 }, true)
	mesa(land, "EastOutcrop", 142, -2, 62, 92, { 14, 11, 8 }, true)
	dune(land, "WestDune", -146, 70, 46, 60, 5)
	dune(land, "EastDune", 146, 76, 46, 60, 5)
	dune(land, "SouthWestDune", -118, 140, 64, 40, 5)
	dune(land, "SouthEastDune", 118, 140, 64, 40, 5)

	-- Sparse vegetation and small rocks, only near the bases of landforms (never near spawn or the mine).
	local plants = Instance.new("Folder")
	plants.Name = "Vegetation"
	plants.Parent = land
	local rng = Random.new(Config.Site.Seed)
	scrub(plants, rng, -70, -104, 70, 14, 5)
	scrub(plants, rng, 52, -112, 80, 14, 5)
	scrub(plants, rng, -110, -34, 12, 70, 4)
	scrub(plants, rng, 110, -2, 12, 70, 4)
	scrub(plants, rng, -126, 78, 12, 40, 3)
	scrub(plants, rng, 126, 84, 12, 40, 3)
	_ = ext
end

return WorldLandscape
