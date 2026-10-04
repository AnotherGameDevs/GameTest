-- Run via tests/run_all.sh. Mine appearance, buried-detail rules and discovery pockets (pure data, no Roblox).
local stubs = require("./_build/shared/__stubs")
local Config = require("./_build/shared/Config")
local Defs = require("./_build/shared/Defs")
local MineStyle = require("./_build/shared/MineStyle")
local MineDetailSpecs = require("./_build/shared/MineDetailSpecs")

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
				local c = MineStyle.Cell(x, y, z, lid, SEED, nil)
				local st = stats[lid]
				st.n += 1
				st.hexes[c.Hex] = true
				st.tones[c.Tone] = (st.tones[c.Tone] or 0) + 1
				st.mats[c.Material] = true
				local again = MineStyle.Cell(x, y, z, lid, SEED, nil)
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
			local c = MineStyle.Cell(bx * 3 + dx, dy, bz * 3 + dz, "Soil", SEED, nil)
			local isPatch = c.Tone == "patch"
			if first == nil then first = isPatch elseif first ~= isPatch then coherent = false end
		end end end
	end end
	check("soil patches are coherent regions", coherent)
	check("a different seed rearranges the mine", MineStyle.Cell(5, 1, 5, "Soil", 1, nil).Hex ~= MineStyle.Cell(5, 1, 5, "Soil", 2, nil).Hex
		or MineStyle.Cell(9, 1, 9, "Soil", 1, nil).Hex ~= MineStyle.Cell(9, 1, 9, "Soil", 2, nil).Hex
		or MineStyle.Cell(3, 1, 12, "Soil", 1, nil).Hex ~= MineStyle.Cell(3, 1, 12, "Soil", 2, nil).Hex)
	check("pocket cells use the pocket tint", MineStyle.Cell(4, 7, 4, "Clay", SEED, "Cache").Tone == "pocket")
end

-- ------------------------------------------------------------------- details ------------------------------------------
do
	local allowed = {}
	for lid, kinds in pairs(MineStyle.AMBIENT) do
		allowed[lid] = {}
		for _, k in ipairs(kinds) do allowed[lid][k] = true; check("ambient kind has specs: " .. k, MineDetailSpecs.Has(k)) end
	end
	-- tells: every treasure id can show a piece of ITSELF; chance follows rarity
	local ids = {}
	for tid in pairs(Defs.Treasure) do table.insert(ids, tid) end
	table.sort(ids)
	local ambient, total, ambientTell, wrongTell, lootAmbient = 0, 0, 0, 0, 0
	local badAmbient = 0
	local tellRate, tellTrials = {}, {}
	for y = 0, S.Depth - 1 do
		local lid = layerOf(y)
		for x = 0, S.SizeX - 1 do for z = 0, S.SizeZ - 1 do
			total += 1
			local d = MineStyle.Detail(x, y, z, lid, SEED, nil, nil)
			if d then
				ambient += 1
				if d.Tell then ambientTell += 1 end
				if not allowed[lid][d.Kind] then badAmbient += 1 end
			end
			for _, tid in ipairs(ids) do
				local dl = MineStyle.Detail(x, y, z, lid, SEED, tid, nil)
				tellTrials[tid] = (tellTrials[tid] or 0) + 1
				if dl then
					tellRate[tid] = (tellRate[tid] or 0) + 1
					if not dl.Tell or dl.Loot ~= tid or dl.Kind ~= "tell" then wrongTell += 1 end
				end
			end
		end end
	end
	check("only layer-appropriate ambient kinds", badAmbient == 0)
	check("ambient remnants are occasional (3-10% of cells)", ambient / total > 0.03 and ambient / total < 0.10, ("%.3f"):format(ambient / total))
	check("ambient cells never claim to be rewards", ambientTell == 0)
	check("a tell always names the cell's own reward", wrongTell == 0)
	for _, tid in ipairs(ids) do
		local want = Config.Mine.TellChance[Defs.Treasure[tid].Rarity]
		local got = (tellRate[tid] or 0) / tellTrials[tid]
		check("tell chance follows rarity: " .. tid, math.abs(got - want) < 0.06, ("%.2f vs %.2f"):format(got, want))
	end
	-- pocket cells: ambient uses the pocket's own remnant
	local kindsSeen = {}
	for x = 0, 23 do local d = MineStyle.Detail(x, 7, 5, "Clay", SEED, nil, "Cache"); if d then kindsSeen[d.Kind] = true end end
	check("cache pocket remnants are pottery sherds", kindsSeen.sherds and next(kindsSeen, "sherds") == nil)
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
	-- every ambient remnant (all variants): bounded, on the face, embedded in the wall, low
	local ambientOk, embeddedOk, lowOk, boundedOk = true, true, true, true
	for _, kind in ipairs(MineDetailSpecs.Kinds) do
		for variant = 0, 3 do
			local specs = MineDetailSpecs.Build(kind, variant)
			if #specs < 2 or #specs > 12 then boundedOk = false end
			local maxZ, minZ = -1e9, 1e9
			for _, sp in ipairs(specs) do
				local x0, x1, y0, y1, z0, z1 = extent(sp)
				maxZ, minZ = math.max(maxZ, z1), math.min(minZ, z0)
				if x0 < -2.05 or x1 > 2.05 or y0 < -2.05 or y1 > 2.05 then ambientOk = false end
			end
			if not (minZ < 0 and minZ > -0.2) then embeddedOk = false end
			if maxZ > 0.16 then lowOk = false end
		end
	end
	check("ambient remnants: bounded part counts", boundedOk)
	check("ambient remnants: stay on their 4x4 face", ambientOk)
	check("ambient remnants: embedded in the wall (nothing floats)", embeddedOk)
	check("ambient remnants: low relief (<= 0.16 studs)", lowOk)
	-- tells: the REAL artifact, partly out of the wall, never fully buried, never wider than the cell face
	local shown, protrudes, onFace = true, true, true
	for tid, def in pairs(Defs.Treasure) do
		for variant = 0, 3 do
			local specs = MineDetailSpecs.Tell(tid, def, variant)
			if #specs < 1 then shown = false end
			local maxZ = -1e9
			for _, sp in ipairs(specs) do
				local x0, x1, y0, y1, _, z1 = extent(sp)
				maxZ = math.max(maxZ, z1)
				if x0 < -2.1 or x1 > 2.1 or y0 < -2.1 or y1 > 2.1 then onFace = false end
			end
			if math.abs(maxZ - Config.Mine.TellProtrude) > 0.06 then protrudes = false end
		end
	end
	check("tells: every treasure shows part of itself", shown)
	check("tells: stand TellProtrude studs out of the wall", protrudes)
	check("tells: never wider than the cell face", onFace)
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
