-- Run via tests/run_all.sh. Structural checks on the rebuilt artifact models: deliberate construction (one connected piece),
-- no glow, sensible size, and the specific shape requirements (open ring, curved two-tone shard, spiral fossil, ...).
local Config = require("./_build/shared/Config")
local Defs = require("./_build/shared/Defs")
local TreasureModels = require("./_build/shared/TreasureModels")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

local function box(s)
	local r = s.Offset.r
	local hx, hy, hz = s.Size.X / 2, s.Size.Y / 2, s.Size.Z / 2
	local ex = math.abs(r[1]) * hx + math.abs(r[2]) * hy + math.abs(r[3]) * hz
	local ey = math.abs(r[4]) * hx + math.abs(r[5]) * hy + math.abs(r[6]) * hz
	local ez = math.abs(r[7]) * hx + math.abs(r[8]) * hy + math.abs(r[9]) * hz
	local p = s.Offset.p
	return { p.X - ex, p.X + ex, p.Y - ey, p.Y + ey, p.Z - ez, p.Z + ez }
end
local function touches(a, b, tol)
	return a[1] <= b[2] + tol and b[1] <= a[2] + tol and a[3] <= b[4] + tol and b[3] <= a[4] + tol and a[5] <= b[6] + tol and b[5] <= a[6] + tol
end
local function components(specs)
	local boxes, parent = {}, {}
	for i, s in ipairs(specs) do boxes[i] = box(s); parent[i] = i end
	local function find(i) while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end return i end
	for i = 1, #specs do for j = i + 1, #specs do
		if touches(boxes[i], boxes[j], 0.03) then parent[find(i)] = find(j) end
	end end
	local roots, n = {}, 0
	for i = 1, #specs do local r = find(i); if not roots[r] then roots[r] = true; n += 1 end end
	return n
end
local function rgb(c)
	local h = c.Hex or ""
	return tonumber(h:sub(1, 2), 16) or 0, tonumber(h:sub(3, 4), 16) or 0, tonumber(h:sub(5, 6), 16) or 0
end
local function named(specs, prefix) local n = 0; for _, s in ipairs(specs) do if s.Name:sub(1, #prefix) == prefix then n += 1 end end return n end
local function find(specs, name) for _, s in ipairs(specs) do if s.Name == name then return s end end end

local ids = {}
for id in pairs(Defs.Treasure) do table.insert(ids, id) end
table.sort(ids)

for _, id in ipairs(ids) do
	local def = Defs.Treasure[id]
	local specs = TreasureModels.Specs(id, def)
	check(id .. ": has a dedicated model", def.Model ~= nil and #specs >= 5)
	local glow = false
	for _, s in ipairs(specs) do if s.Material == "Material.Neon" or tostring(s.Material):find("Neon") then glow = true end end
	check(id .. ": no neon/glow material", not glow)
	check(id .. ": built as ONE connected piece (no floating parts)", components(specs) == 1, tostring(components(specs)) .. " pieces")
	local ext = TreasureModels.MaxExtent(specs)
	check(id .. ": reasonable size 1.8-4.2 studs", ext >= 1.8 and ext <= 4.2, ("%.2f"):format(ext))
	local fit = TreasureModels.MaxExtent(require("./_build/shared/ModelKit").Transform(specs, 1.8 / ext, nil))
	check(id .. ": display fit lands on the target size", math.abs(fit - 1.8) < 0.02, ("%.3f"):format(fit))
end

-- old coin: thin round, rim + face + raised emblem
do
	local s = TreasureModels.Specs("old_coin", Defs.Treasure.old_coin)
	local rim, face = find(s, "Rim"), find(s, "Face")
	check("coin: thin (thickness < 0.45 of diameter/4)", rim and rim.Size.X < 0.5 and rim.Size.Y >= 2.2)
	check("coin: defined rim (rim wider than face)", rim and face and rim.Size.Y > face.Size.Y)
	check("coin: raised emblem (sunburst rays)", named(s, "Ray") == 4 and find(s, "EmblemDisc") ~= nil)
end

-- bronze ring: an open band, thickened top, bezel detail, bronze colours with some patina
do
	local s = TreasureModels.Specs("bronze_ring", Defs.Treasure.bronze_ring)
	check("ring: at least 11 band segments + bezel", named(s, "Band") >= 11 and find(s, "Bezel") ~= nil)
	local blocked = false
	for _, p in ipairs(s) do
		if p.Name:sub(1, 4) == "Band" then
			local r, c = p.Offset.r, p.Offset.p
			for sx = -1, 1, 2 do for sy = -1, 1, 2 do
				local lx, ly = sx * p.Size.X / 2, sy * p.Size.Y / 2
				local x, y = c.X + r[1] * lx + r[2] * ly, c.Y + r[4] * lx + r[5] * ly
				if math.sqrt(x * x + y * y) < 0.7 then blocked = true end
			end end
		end
	end
	check("ring: the interior opening is clear", not blocked)
	local bez = find(s, "Bezel")
	check("ring: top section is thicker than the band", bez and bez.Size.Y > 0.34 + 0.2)
	check("ring: raised detail on the bezel", find(s, "Emblem") ~= nil)
	local r, g, b = rgb(find(s, "Band0").Color)
	check("ring: muted bronze (R > G > B)", r > g and g > b and r < 200)
	check("ring: restrained patina on some segments", find(s, "Band4") and select(2, rgb(find(s, "Band4").Color)) > select(1, rgb(find(s, "Band4").Color)) * 0.9)
	check("ring: display is tilted toward the viewer", (TreasureModels.DisplayPitch.bronze_ring or 0) <= -20)
end

-- clay figurine
do
	local s = TreasureModels.Specs("clay_figurine", Defs.Treasure.clay_figurine)
	for _, n in ipairs({ "Base", "LowerTorso", "UpperTorso", "Neck", "Head", "ArmL", "UpperArmR", "ForearmR", "Chip", "Nose", "EyeL", "Mouth" }) do
		check("figurine: has " .. n, find(s, n) ~= nil)
	end
	check("figurine: tapered torso (upper narrower than lower)", find(s, "UpperTorso").Size.X < find(s, "LowerTorso").Size.X)
	check("figurine: neck is narrower than the head", find(s, "Neck").Size.Y < find(s, "Head").Size.X)
	check("figurine: stable base wider than the torso", find(s, "Base").Size.X > find(s, "LowerTorso").Size.X)
	check("figurine: arms differ in pose (one hangs, one bent)", find(s, "ArmL").Offset.p.Z ~= find(s, "ForearmR").Offset.p.Z)
	local ok = true
	for _, n in ipairs({ "LowerTorso", "UpperTorso", "ArmL", "Base" }) do
		local r, g, b = rgb(find(s, n).Color)
		if not (r > g and g > b and r >= 90) then ok = false end
	end
	check("figurine: terracotta colours (not pale yellow plastic)", ok)
end

-- fossil fragment
do
	local s = TreasureModels.Specs("fossil_fragment", Defs.Treasure.fossil_fragment)
	check("fossil: irregular slab (>= 4 rock pieces)", named(s, "Slab") + named(s, "Chunk") + named(s, "Chip") >= 4)
	check("fossil: spiral of >= 10 shell segments with ribs", named(s, "Shell") >= 10 and named(s, "Rib") >= 10)
	local cyl = false
	for _, p in ipairs(s) do if p.Shape == "Cylinder" then cyl = true end end
	check("fossil: no concentric discs", not cyl)
	-- the spiral grows outward: later segments are farther from the centre
	local function dist(n) local p = find(s, n).Offset.p; return math.sqrt((p.X + 0.1) ^ 2 + (p.Y - 0.05) ^ 2) end
	check("fossil: whorls follow a growing spiral", dist("Shell11") > dist("Shell6") and dist("Shell6") > dist("Shell0"))
	local br, bg = rgb(find(s, "Shell5").Color); local sr = rgb(find(s, "Slab").Color)
	check("fossil: bone is clearly lighter than the rock", br - sr > 60)
end

-- necklace
do
	local s = TreasureModels.Specs("ancient_necklace", Defs.Treasure.ancient_necklace)
	check("necklace: beaded loop (>= 14 beads) with links", named(s, "Bead") >= 14 and named(s, "Link") >= 14)
	check("necklace: pendant with shaped setting and inset stone", find(s, "Setting") and find(s, "SettingRim") and find(s, "InsetStone") and find(s, "Bail"))
	check("necklace: on a neutral stand", find(s, "StandBase") and find(s, "StandColumn") and find(s, "Bust"))
	check("necklace: the stone is glass, not glow", find(s, "InsetStone").Material == "Material.Glass" or tostring(find(s, "InsetStone").Material):find("Glass") ~= nil)
	local r, g, b = rgb(find(s, "Bead1").Color)
	check("necklace: aged gold (muted: R < 215)", r > g and g > b and r < 215)
end

-- pottery shard
do
	local s = TreasureModels.Specs("pottery_shard", Defs.Treasure.pottery_shard)
	check("shard: curved wall of >= 7 segments", named(s, "Outer") >= 7 and named(s, "Inner") >= 7)
	local o, i = find(s, "Outer3"), find(s, "Inner3")
	check("shard: visible wall thickness (inner and outer layers offset)", o and i and (o.Offset.p - i.Offset.p).Magnitude > 0.15)
	check("shard: inner and outer tones differ", rgb(o.Color) - rgb(i.Color) > 40)
	check("shard: uneven top edge (heights vary)", find(s, "Outer4").Size.Y ~= find(s, "Outer2").Size.Y and find(s, "Outer1").Size.Y < find(s, "Outer4").Size.Y)
	check("shard: painted band and dots", named(s, "Band") >= 3 and named(s, "Dot") >= 3)
	check("shard: curved (middle segment bulges forward of the ends)", find(s, "Outer4").Offset.p.Z > find(s, "Outer1").Offset.p.Z)
end

-- claw / tablet / gem / scarab / mask basic intent
do
	local claw = TreasureModels.Specs("fossil_claw", Defs.Treasure.fossil_claw)
	check("claw: six tapering segments", named(claw, "Seg") == 6 and find(claw, "Seg5").Size.Y < find(claw, "Seg0").Size.Y * 0.4)
	local tab = TreasureModels.Specs("ruin_tablet", Defs.Treasure.ruin_tablet)
	check("tablet: border + 12 carved glyphs + chip + crack", named(tab, "Glyph") == 12 and named(tab, "Border") == 4 and find(tab, "Chip") and find(tab, "Crack"))
	local gem = TreasureModels.Specs("cut_gemstone", Defs.Treasure.cut_gemstone)
	check("gem: faceted stack (>= 8 layers)", #gem >= 8)
	local mask = TreasureModels.Specs("sun_mask", Defs.Treasure.sun_mask)
	check("mask: face, headdress, eyes, nose, beard", find(mask, "Face") and find(mask, "HeadCloth") and find(mask, "EyeL") and find(mask, "Nose") and find(mask, "Beard"))
	local sc = TreasureModels.Specs("golden_scarab", Defs.Treasure.golden_scarab)
	check("scarab: shell, head and six legs", find(sc, "Shell") and find(sc, "Head") and named(sc, "Leg") == 6)
end

-- mesh pipeline: until meshes are configured the seven mesh-required artifacts are reported UNFINISHED; configuring a mesh set switches
-- EVERY consumer (they all call Specs) to it, and scaling keeps the mesh data
do
	local Kit = require("./_build/shared/ModelKit")
	local required = TreasureModels.MeshRequired
	local unfinished = true
	for _, id in ipairs(required) do if TreasureModels.Status(id) ~= "unfinished" then unfinished = false end end
	check("seven artifacts are honestly marked unfinished until meshes are imported", #required == 7 and unfinished)
	check("coin and ring primitives are final art", TreasureModels.Status("old_coin") == "parts" and TreasureModels.Status("bronze_ring") == "parts")
	local V = require("./_build/shared/__stubs").Vector3
	Config.MeshAssets.pottery_shard = { { Name = "outer", MeshId = "rbxassetid://1", Color = "B5683F", Material = "SmoothPlastic", Size = V.new(2.5, 2.5, 0.9) } }
	local specs = TreasureModels.Specs("pottery_shard", Defs.Treasure.pottery_shard)
	check("a configured mesh set replaces the primitive fallback", TreasureModels.Status("pottery_shard") == "mesh" and #specs == 1 and specs[1].Shape == "Mesh" and specs[1].MeshId == "rbxassetid://1")
	local scaled = Kit.Transform(specs, 0.5, nil)
	check("scaling keeps the mesh id and native size", scaled[1].MeshId == "rbxassetid://1" and scaled[1].MeshSize.X == 2.5 and math.abs(scaled[1].Size.X - 1.25) < 1e-6)
	Config.MeshAssets.pottery_shard = nil
	check("removing the mesh set restores the fallback", TreasureModels.Status("pottery_shard") == "unfinished")
end

print(("artifact models: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
