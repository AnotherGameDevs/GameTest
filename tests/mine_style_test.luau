-- Run via tests/run_all.sh. Mine appearance, buried-detail rules and discovery pockets (pure data, no Roblox).
local stubs = require("./_build/shared/__stubs")
local Config = require("./_build/shared/Config")
local Defs = require("./_build/shared/Defs")
local MineStyle = require("./_build/shared/MineStyle")
local MineDetailSpecs = require("./_build/shared/MineDetailSpecs")
local TreasureModels = require("./_build/shared/TreasureModels")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

local S = Config.Site
local SEED = Config.Site.Seed
local function layerOf(y) return Defs.LayerAtCell(y).Id end

-- ------------------------------------------------------------------- hash --------------------------------------------
do
	local lo, hi, same = 1, 0, true
	for i = 1, 500 do
		local h = MineStyle.Hash(i, i * 3 % 20, i * 7 % 24, SEED, 5)
		lo, hi = math.min(lo, h), math.max(hi, h)
		if h ~= MineStyle.Hash(i, i * 3 % 20, i * 7 % 24, SEED, 5) then same = false end
	end
	check("hash is deterministic", same)
	check("hash stays in [0,1) and spreads out", lo >= 0 and hi < 1 and hi - lo > 0.9)
end

-- ------------------------------------------------------------------- cell styles -------------------------------------
do
	local stats = {}
	for _, l in ipairs(Config.Layers) do stats[l.Id] = { n = 0, hexes = {}, tones = {}, mats = {} } end
	for y = 0, S.Depth - 1 do
		local lid = layerOf(y)
		for x = 0, S.SizeX - 1 do
			for z = 0, S.SizeZ - 1 do
				local c = MineStyle.Cell(x, y, z, lid, SEED)
				local st = stats[lid]
				st.n += 1
				st.hexes[c.Hex] = true
				st.tones[c.Tone] = (st.tones[c.Tone] or 0) + 1
				st.mats[c.Material] = true
				local again = MineStyle.Cell(x, y, z, lid, SEED)
				if again.Hex ~= c.Hex or again.Material ~= c.Material then check("cell style is deterministic", false) end
			end
		end
	end
	for lid, st in pairs(stats) do
		local nh = 0
		for _ in pairs(st.hexes) do nh += 1 end
		local nm = 0
		for _ in pairs(st.mats) do nm += 1 end
		check(lid .. ": a small coherent palette (<= 9 colours)", nh >= 3 and nh <= 9, tostring(nh))
		check(lid .. ": exactly one material", nm == 1)
	end
	local seams = (stats.Stone.tones.seam or 0) / stats.Stone.n
	check("stone seams are restrained (1-8% of cells)", seams > 0.01 and seams < 0.08, ("%.3f"):format(seams))
	local carved = (stats.Ruins.tones.carved or 0) / stats.Ruins.n
	check("ruins carved blocks are rare (<= 6%)", carved > 0.005 and carved <= 0.06, ("%.3f"):format(carved))
	check("clay shows bands", (stats.Clay.tones.band or 0) / stats.Clay.n > 0.8)
	-- patches, not per-cell noise: inside one 3x2x3 region soil patch tone is all-or-nothing
	local coherent = true
	for bx = 0, 6 do for bz = 0, 6 do
		local first
		for dx = 0, 2 do for dy = 0, 1 do for dz = 0, 2 do
			local c = MineStyle.Cell(bx * 3 + dx, dy, bz * 3 + dz, "Soil", SEED)
			local isPatch = c.Tone == "patch"
			if first == nil then first = isPatch elseif first ~= isPatch then coherent = false end
		end end end
	end end
	check("soil patches are coherent regions", coherent)
	check("a different seed rearranges the mine", MineStyle.Cell(5, 1, 5, "Soil", 1).Hex ~= MineStyle.Cell(5, 1, 5, "Soil", 2).Hex
		or MineStyle.Cell(9, 1, 9, "Soil", 1).Hex ~= MineStyle.Cell(9, 1, 9, "Soil", 2).Hex
		or MineStyle.Cell(3, 1, 12, "Soil", 1).Hex ~= MineStyle.Cell(3, 1, 12, "Soil", 2).Hex)
	check("no cell is ever tinted as a discovery pocket (pockets have no visual marker)", (function()
		for y = 0, S.Depth - 1 do for x = 0, 23 do for z = 0, 23 do if MineStyle.Cell(x, y, z, layerOf(y), SEED).Tone == "pocket" then return false end end end end
		return true
	end)())
end

-- ------------------------------------------------------------------- pre-discovery rule -------------------------------
-- An intact block must show NO reward, rarity clue or hint of where rewards are. Everything drawn on a mine cell comes from
-- MineStyle.Detail -> MineDetailSpecs, which have no access to the buried loot; these checks pin that down.
do
	local allowed = {}
	for lid, kinds in pairs(MineStyle.AMBIENT) do
		allowed[lid] = {}
		for _, k in ipairs(kinds) do allowed[lid][k] = true; check("ambient kind has specs: " .. k, MineDetailSpecs.Has(k)) end
	end
	-- the API takes no loot / pocket argument and exposes no tell machinery
	check("Detail has no loot parameter (arity 5: x, y, z, layer, seed)", debug.info(MineStyle.Detail, "a") == 5)
	check("no tell / treasure code exists in the mine remnant modules", MineDetailSpecs.Tell == nil and MineStyle.TELLS == nil and MineStyle.POCKET_AMBIENT == nil)
	local ambient, total, badKind, tellish = 0, 0, 0, 0
	for y = 0, S.Depth - 1 do
		local lid = layerOf(y)
		for x = 0, S.SizeX - 1 do for z = 0, S.SizeZ - 1 do
			total += 1
			local d = MineStyle.Detail(x, y, z, lid, SEED)
			if d then
				ambient += 1
				if not allowed[lid][d.Kind] then badKind += 1 end
				if d.Tell ~= nil or d.Loot ~= nil or d.Kind == "tell" then tellish += 1 end
			end
		end end
	end
	check("only layer-appropriate ambient kinds", badKind == 0)
	check("no detail is a reward tell or carries a loot reference", tellish == 0)
	check("ambient remnants are occasional (3-10% of cells)", ambient / total > 0.03 and ambient / total < 0.10, ("%.3f"):format(ambient / total))
	-- the remnant kinds must not look like collectibles
	local forbidden = { "sherds", "fossil_impression", "worked_fragment", "carving", "coin", "ring", "necklace", "gem", "tablet", "tell" }
	local clean = true
	for _, kind in ipairs(MineDetailSpecs.Kinds) do
		for _, f in ipairs(forbidden) do if kind:find(f, 1, true) then clean = false end end
	end
	check("no remnant is named or shaped like a collectible", clean)
	-- remnant colours/materials can never coincide with a treasure model's colours, and are never shiny
	local reward = {}
	for id, def in pairs(Defs.Treasure) do
		for _, sp in ipairs(TreasureModels.Specs(id, def)) do reward[sp.Color.Hex or tostring(sp.Color)] = true end
	end
	local colourClash, shiny = false, false
	for _, kind in ipairs(MineDetailSpecs.Kinds) do
		for _, sp in ipairs(MineDetailSpecs.Build(kind, 0)) do
			if reward[sp.Color.Hex or tostring(sp.Color)] then colourClash = true end
			local m = tostring(sp.Material)
			if m:find("Metal") or m:find("Glass") or m:find("Neon") then shiny = true end
		end
	end
	check("remnants never use a treasure colour", not colourClash)
	check("remnants are never metal, glass or neon", not shiny)
end

-- ------------------------------------------------------------------- detail geometry ------------------------------------
do
	local function extent(spec)
		local r = spec.Offset.r
		local hx, hy, hz = spec.Size.X / 2, spec.Size.Y / 2, spec.Size.Z / 2
		local ex = math.abs(r[1]) * hx + math.abs(r[2]) * hy + math.abs(r[3]) * hz
		local ey = math.abs(r[4]) * hx + math.abs(r[5]) * hy + math.abs(r[6]) * hz
		local ez = math.abs(r[7]) * hx + math.abs(r[8]) * hy + math.abs(r[9]) * hz
		local p = spec.Offset.p
		return p.X - ex, p.X + ex, p.Y - ey, p.Y + ey, p.Z - ez, p.Z + ez
	end
	local onFace, embedded, low, bounded = true, true, true, true
	for _, kind in ipairs(MineDetailSpecs.Kinds) do
		for variant = 0, 3 do
			local specs = MineDetailSpecs.Build(kind, variant)
			if #specs < 2 or #specs > 12 then bounded = false end
			local maxZ, minZ = -1e9, 1e9
			for _, sp in ipairs(specs) do
				local x0, x1, y0, y1, z0, z1 = extent(sp)
				maxZ, minZ = math.max(maxZ, z1), math.min(minZ, z0)
				if x0 < -2.05 or x1 > 2.05 or y0 < -2.05 or y1 > 2.05 then onFace = false end
			end
			if not (minZ < 0 and minZ > -0.2) then embedded = false end
			if maxZ > 0.16 then low = false end
		end
	end
	check("remnants: bounded part counts", bounded)
	check("remnants: stay on their 4x4 face", onFace)
	check("remnants: embedded in the wall (nothing floats)", embedded)
	check("remnants: low relief (<= 0.16 studs)", low)
end

-- ------------------------------------------------------------------- pockets -------------------------------------------
do
	local layers = {}
	for i, l in ipairs(Config.Layers) do layers[l.Id] = { l.FromCell, (Config.Layers[i + 1] and Config.Layers[i + 1].FromCell or S.Depth) - 1 } end
	for _, seed in ipairs({ SEED, 424242, 7919, 1, 99991, 2147483000 }) do
		local pockets = MineStyle.Pockets(seed)
		local counts, seen, ok = { Cache = 0, Fossil = 0, Masonry = 0 }, {}, true
		local lootOk, sizeOk = true, true
		for _, p in ipairs(pockets) do
			counts[p.Kind] += 1
			local minx, maxx, miny, maxy, minz, maxz = 99, -99, 99, -99, 99, -99
			for _, c in ipairs(p.Cells) do
				local x, y, z = c[1], c[2], c[3]
				local key = x .. "," .. y .. "," .. z
				if seen[key] then ok = false end
				seen[key] = true
				if x < 1 or x > S.SizeX - 2 or z < 1 or z > S.SizeZ - 2 then ok = false end
				if y < layers[p.Layer][1] or y > layers[p.Layer][2] then ok = false end
				if c[4] and not Defs.Treasure[c[4]] then lootOk = false end
				minx, maxx, miny, maxy, minz, maxz = math.min(minx, x), math.max(maxx, x), math.min(miny, y), math.max(maxy, y), math.min(minz, z), math.max(maxz, z)
			end
			if maxx - minx > 2 or maxy - miny > 1 or maxz - minz > 2 then sizeOk = false end
		end
		check(("seed %d: pocket cells inside the grid, in their layer, non-overlapping"):format(seed), ok)
		check(("seed %d: pockets are compact (<= 3x2x3)"):format(seed), sizeOk)
		check(("seed %d: pocket loot ids are real treasures"):format(seed), lootOk)
		check(("seed %d: every configured pocket was placed"):format(seed),
			counts.Cache == Config.Mine.Pockets.Cache and counts.Fossil == Config.Mine.Pockets.Fossil and counts.Masonry == Config.Mine.Pockets.Masonry)
		local again = MineStyle.Pockets(seed)
		local same = #again == #pockets
		for i, p in ipairs(pockets) do if not again[i] or again[i].Cells[1][1] ~= p.Cells[1][1] or again[i].Cells[1][3] ~= p.Cells[1][3] then same = false end end
		check(("seed %d: pocket placement is deterministic (no duplicates on regeneration)"):format(seed), same)
	end
	local a, b = MineStyle.Pockets(SEED), MineStyle.Pockets(SEED + 7919)
	check("a refreshed mine moves its pockets", a[1].Cells[1][1] ~= b[1].Cells[1][1] or a[1].Cells[1][3] ~= b[1].Cells[1][3] or a[2].Cells[1][1] ~= b[2].Cells[1][1])
	-- tier appropriateness: pocket layers are open to the tool tiers that can reach them in normal progression
	check("cache is in clay, fossil in stone, masonry in ruins", MineStyle.POCKET_LAYER.Cache == "Clay" and MineStyle.POCKET_LAYER.Fossil == "Stone" and MineStyle.POCKET_LAYER.Masonry == "Ruins")
end

print(("mine style: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
