-- Pure, deterministic description of how the mine LOOKS and where small buried discoveries sit (no Roblox instances).
-- Everything is a function of (cell, layer, seed), so every client/server agrees, regeneration with the same seed
-- reproduces it exactly, and a new seed (mine refresh) gives a new arrangement. Tested in tests/mine_style_test.luau.
--   * Cell(): colour + material per cell, built from PATCHES (blocky 3x2x3 regions) and wavy BANDS (strata), never
--     per-cell noise. Each layer has a small palette.
--   * Detail(): which small remnant (if any) a cell carries, and whether it is an ambient remnant or a "tell" of the
--     cell's REAL loot. Reward tells only appear on cells that really hold that reward; ambient remnants never appear on
--     loot cells and never use treasure colours.
--   * Pockets(): a few compact discovery pockets (pottery cache in clay, fossil patch in stone, broken masonry in ruins).
local Config = require(script.Parent.Config)

local MineStyle = {}

local MOD = 4294967296

-- Exact 32-bit integer hash (all intermediate products stay below 2^53, so the result is identical everywhere).
local function hash(x: number, y: number, z: number, seed: number, salt: number): number
	local h = bit32.bxor((x * 73856093) % MOD, (y * 19349663) % MOD, (z * 83492791) % MOD, (seed * 2654435) % MOD, (salt * 40503) % MOD)
	h = (h * 1664525 + 1013904223) % MOD
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (h * 1664525 + 1013904223) % MOD
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1664525 + 1013904223) % MOD
	return h / MOD
end
MineStyle.Hash = hash

-- Palettes ---------------------------------------------------------------------------------------------------------
-- Colours are hex strings; materials are Enum.Material member names (converted by the caller).
local PALETTE = {
	Soil = { Material = "Ground", Base = { "9A623A", "93603A" }, Dark = "82522F", Light = "A9714A" },
	Clay = { Material = "Sandstone", Base = { "C97846", "C27244" }, Band = { "B5683F", "D08550", "BE6F43" }, Lens = "D9A06A" },
	Stone = { Material = "Slate", Base = { "68717C", "646D78" }, Dark = "59626D", Light = "77818C", Seam = { "6F9A9B", "A9B4B8" } },
	Ruins = { Material = "Limestone", Base = { "D8B678", "D2B073" }, Course = "C7A667", Patch = "BE9E63", Carved = "A98A55" },
}
local POCKET_STYLE = { -- tinted regions that mark a discovery pocket as it is uncovered (subtle, same family as the layer)
	Cache = { Hex = "9A4E2E", Alt = "B5683F", Material = "Sandstone" },
	Fossil = { Hex = "8A8F96", Alt = "A39F92", Material = "Slate" },
	Masonry = { Hex = "CDBB92", Alt = "B09A6E", Material = "Limestone" },
}
MineStyle.POCKET_LAYER = { Cache = "Clay", Fossil = "Stone", Masonry = "Ruins" }

local function pick(list, h: number)
	return list[math.min(#list, math.floor(h * #list) + 1)]
end

-- Wavy strata index: rows in the same band share a tone, and the band edge ripples gently across x/z.
local function band(x: number, y: number, z: number, thickness: number, seed: number): number
	local warp = math.sin(x * 0.55 + seed * 0.1) * 0.7 + math.cos(z * 0.45 + seed * 0.3) * 0.7
	return math.floor((y + warp) / thickness)
end

-- Appearance of one cell. Returns { Hex, Material, Tone }.
function MineStyle.Cell(x: number, y: number, z: number, layerId: string, seed: number, pocketKind: string?)
	local pal = PALETTE[layerId] or PALETTE.Soil
	local patch = hash(x // 3, y // 2, z // 3, seed, 1) -- one value per 3x2x3 region: patches, not noise
	if pocketKind then
		local ps = POCKET_STYLE[pocketKind]
		if ps then
			local alt = (x + z + y) % 2 == 0
			return { Hex = alt and ps.Hex or ps.Alt, Material = ps.Material, Tone = "pocket" }
		end
	end
	if layerId == "Soil" then
		local hex = pick(pal.Base, hash(x, y, z, seed, 2))
		local tone = "base"
		if patch < 0.22 then hex, tone = pal.Dark, "patch" elseif patch > 0.84 then hex, tone = pal.Light, "patch" end
		return { Hex = hex, Material = pal.Material, Tone = tone }
	elseif layerId == "Clay" then
		local b = band(x, y, z, 1, seed)
		local hex, tone = pick(pal.Band, hash(b, 0, 0, seed, 3)), "band"
		if patch > 0.9 then hex, tone = pal.Lens, "patch" end
		return { Hex = hex, Material = pal.Material, Tone = tone }
	elseif layerId == "Stone" then
		local hex, tone = pick(pal.Base, hash(x, y, z, seed, 4)), "base"
		if patch < 0.2 then hex, tone = pal.Dark, "patch" elseif patch > 0.86 then hex, tone = pal.Light, "patch" end
		-- restrained mineral seams: thin diagonal planes, only on some cells of the plane
		local plane = (x * 2 + z * 3 + y * 5 + seed) % 19
		if plane == 0 and hash(x, y, z, seed, 5) < 0.55 then
			hex, tone = pick(pal.Seam, hash(x, y, z, seed, 6)), "seam"
		end
		return { Hex = hex, Material = pal.Material, Tone = tone }
	else -- Ruins: courses of worked stone (alternate rows), a few weathered patches and rare carved blocks
		local hex, tone = pick(pal.Base, hash(x, y, z, seed, 7)), "base"
		if (y + (x // 2)) % 2 == 1 then hex, tone = pal.Course, "course" end
		if patch < 0.16 then hex, tone = pal.Patch, "patch" end
		if hash(x, y, z, seed, 8) < 0.04 then hex, tone = pal.Carved, "carved" end
		return { Hex = hex, Material = pal.Material, Tone = tone }
	end
end

-- Details -----------------------------------------------------------------------------------------------------------
MineStyle.AMBIENT = { -- remnants by layer (exactly the set asked for: roots/stones in soil, pottery in clay, seams + fossil
	Soil = { "roots", "pebbles" }, -- impressions in stone, worked fragments + carvings in the ruins)
	Clay = { "sherds" },
	Stone = { "seam", "fossil_impression" },
	Ruins = { "worked_fragment", "carving" },
}
MineStyle.POCKET_AMBIENT = { Cache = "sherds", Fossil = "fossil_impression", Masonry = "worked_fragment" }
-- Rewards whose real cell shows a tell when its face is exposed. The tell IS the reward (same treasure id).
MineStyle.TELLS = { old_coin = "tell_coin", pottery_shard = "tell_pottery", fossil_fragment = "tell_fossil", ruin_tablet = "tell_tablet" }

-- Returns nil or { Kind, Variant (0-3), FaceRot (0-5), Tell (bool), Loot (treasure id for tells) }.
function MineStyle.Detail(x: number, y: number, z: number, layerId: string, seed: number, lootId: string?, pocketKind: string?)
	local variant = math.floor(hash(x, y, z, seed, 14) * 4)
	local faceRot = math.floor(hash(x, y, z, seed, 15) * 6)
	if lootId then
		local tell = MineStyle.TELLS[lootId]
		local chance = pocketKind and 0.9 or Config.Mine.TellChance
		if tell and hash(x, y, z, seed, 12) < chance then
			return { Kind = tell, Variant = variant, FaceRot = faceRot, Tell = true, Loot = lootId }
		end
		return nil -- loot cells never carry ambient remnants: a remnant must never promise a reward that is not there
	end
	if pocketKind then
		if hash(x, y, z, seed, 16) < Config.Mine.PocketChance then
			return { Kind = MineStyle.POCKET_AMBIENT[pocketKind], Variant = variant, FaceRot = faceRot, Tell = false }
		end
		return nil
	end
	if hash(x, y, z, seed, 11) >= (Config.Mine.AmbientChance[layerId] or 0) then
		return nil
	end
	local kinds = MineStyle.AMBIENT[layerId]
	if not kinds then
		return nil
	end
	return { Kind = pick(kinds, hash(x, y, z, seed, 13)), Variant = variant, FaceRot = faceRot, Tell = false }
end

-- Pockets -----------------------------------------------------------------------------------------------------------
local function layerRows(layerId: string): (number, number)
	local from, to = 0, Config.Site.Depth - 1
	for i, l in ipairs(Config.Layers) do
		if l.Id == layerId then
			from = l.FromCell
			to = (Config.Layers[i + 1] and Config.Layers[i + 1].FromCell or Config.Site.Depth) - 1
		end
	end
	return from, to
end

-- Pocket shapes: { dx, dy, dz, loot? }. Compact (at most 3x2x3) and fully inside the grid by construction.
local SHAPES = {
	Cache = { { 0, 0, 0, "clay_figurine" }, { 1, 0, 0, "pottery_shard" }, { -1, 0, 0, "pottery_shard" }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 } },
	Fossil = { { -1, 0, -1 }, { 0, 0, -1, "fossil_fragment" }, { 1, 0, -1 }, { -1, 0, 0 }, { 0, 0, 0 }, { 1, 0, 0, "fossil_fragment" },
		{ -1, 0, 1 }, { 0, 0, 1 }, { 1, 0, 1 } },
	Masonry = { { 0, 0, 0, "ruin_tablet" }, { 1, 0, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 0 }, { 1, 1, 0 }, { 0, 1, 1 }, { 1, 1, 1 } },
}
MineStyle.POCKET_ORDER = { "Cache", "Fossil", "Masonry" }

-- Returns a list of { Kind, Layer, Cells = { { x, y, z, Loot? } } }, deterministic in `seed`, non-overlapping.
function MineStyle.Pockets(seed: number)
	local out, used = {}, {}
	local S = Config.Site
	for _, kind in ipairs(MineStyle.POCKET_ORDER) do
		local layerId = MineStyle.POCKET_LAYER[kind]
		local r0, r1 = layerRows(layerId)
		for n = 1, Config.Mine.Pockets[kind] or 0 do
			for attempt = 1, 12 do
				local cx = 2 + math.floor(hash(n, attempt, 1, seed, 100 + #kind) * (S.SizeX - 4))
				local cz = 2 + math.floor(hash(n, attempt, 2, seed, 100 + #kind) * (S.SizeZ - 4))
				local cy = r0 + 1 + math.floor(hash(n, attempt, 3, seed, 100 + #kind) * math.max(r1 - r0 - 2, 1))
				local cells, ok = {}, true
				for _, o in ipairs(SHAPES[kind]) do
					local x, y, z = cx + o[1], cy + o[2], cz + o[3]
					local key = (y * S.SizeZ + z) * S.SizeX + x
					if x < 1 or x > S.SizeX - 2 or z < 1 or z > S.SizeZ - 2 or y < r0 or y > r1 or used[key] then
						ok = false
						break
					end
					table.insert(cells, { x, y, z, o[4], key })
				end
				if ok then
					for _, c in ipairs(cells) do
						used[c[5]] = true
						c[5] = nil
					end
					table.insert(out, { Kind = kind, Layer = layerId, Cells = cells })
					break
				end
			end
		end
	end
	return out
end

return MineStyle
