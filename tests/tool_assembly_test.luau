-- Run: luau tests/tool_assembly_test.luau
-- Proves, using the REAL part specs and viewmodel maths (with minimal Vector3/CFrame stand-ins), that:
--   1. every tool has an invisible origin cube "Handle" root and is ONE connected assembly (no orphaned parts);
--   2. the shaft is vertical (Y), enters the socket/housing, the grip is at the opposite end from the working end;
--   3. in the first-person viewmodel the crosshair area is empty at rest and through the whole swing, at several
--      aspect ratios; the tool sits in the lower right; artifacts held while carrying also leave the view clear.
local stubs = require("./_build/shared/__stubs") -- the SAME instance the prepared modules use
local Vector3, CFrame = stubs.Vector3, stubs.CFrame

local ToolModels = require("./_build/shared/ToolModels")
local Appearances = require("./_build/shared/Appearances")
local ViewmodelMath = require("./_build/shared/ViewmodelMath")
local TreasureModels = require("./_build/shared/TreasureModels")
local Defs = require("./_build/shared/Defs")

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end
end

-- axis-aligned bounds of a (possibly 90-degree-rotated) box
local function bounds(p)
	local r = p.Offset.r
	local hx, hy, hz = p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2
	local ex = math.abs(r[1]) * hx + math.abs(r[2]) * hy + math.abs(r[3]) * hz
	local ey = math.abs(r[4]) * hx + math.abs(r[5]) * hy + math.abs(r[6]) * hz
	local ez = math.abs(r[7]) * hx + math.abs(r[8]) * hy + math.abs(r[9]) * hz
	local c = p.Offset.p
	return { minX = c.X - ex, maxX = c.X + ex, minY = c.Y - ey, maxY = c.Y + ey, minZ = c.Z - ez, maxZ = c.Z + ez, c = c }
end
local function touches(a, b, tol)
	return a.minX <= b.maxX + tol and b.minX <= a.maxX + tol and a.minY <= b.maxY + tol and b.minY <= a.maxY + tol
		and a.minZ <= b.maxZ + tol and b.minZ <= a.maxZ + tol
end

local function byName(parts, name)
	for _, p in ipairs(parts) do if p.Name == name then return p end end
end

-- 1 + 2: assembly --------------------------------------------------------------------------------------------------
local appearanceIds = {}
for id in pairs(Appearances.List) do table.insert(appearanceIds, id) end
table.sort(appearanceIds)

for _, id in ipairs(appearanceIds) do
	local spec = ToolModels.GetSpec(id)
	local parts = spec.Parts
	local root = parts[1]
	check(id .. ": root is Handle", root.Name == "Handle")
	check(id .. ": root invisible cube at origin", root.Transparency == 1 and root.Shape == "Block"
		and root.Offset.p.Magnitude < 1e-6 and root.Offset.r[1] == 1 and root.Offset.r[5] == 1 and root.Offset.r[9] == 1)

	local bs = {}
	for i, p in ipairs(parts) do bs[i] = bounds(p) end
	-- connectivity (BFS from the root)
	local seen, queue = { [1] = true }, { 1 }
	local count = 1
	while #queue > 0 do
		local i = table.remove(queue, 1)
		for j = 1, #parts do
			if not seen[j] and touches(bs[i], bs[j], 0.06) then
				seen[j] = true
				count += 1
				table.insert(queue, j)
			end
		end
	end
	local orphans = {}
	for i = 1, #parts do if not seen[i] then table.insert(orphans, parts[i].Name) end end
	check(id .. ": single connected assembly", #orphans == 0, "orphans: " .. table.concat(orphans, ","))

	-- overall size sanity ("better without becoming enormous")
	local minY, maxY, maxW = math.huge, -math.huge, 0
	for _, b in ipairs(bs) do
		minY, maxY = math.min(minY, b.minY), math.max(maxY, b.maxY)
		maxW = math.max(maxW, b.maxX - b.minX, b.maxZ - b.minZ)
	end
	check(id .. ": length <= 8 studs", maxY - minY <= 8, ("%.2f"):format(maxY - minY))

	if spec.Checks then
		local c = spec.Checks
		local shaft = byName(parts, c.Shaft)
		check(id .. ": shaft exists", shaft ~= nil)
		if shaft then
			local sb = bounds(shaft)
			check(id .. ": shaft runs along Y", (sb.maxY - sb.minY) > (sb.maxX - sb.minX) and (sb.maxY - sb.minY) > (sb.maxZ - sb.minZ))
			check(id .. ": shaft contains the origin", sb.minX <= 0 and sb.maxX >= 0 and sb.minY <= 0 and sb.maxY >= 0)
			-- shaft ENTERS the socket / housing at its +Y end
			local entered = false
			for _, name in ipairs(c.Socket) do
				local s = byName(parts, name)
				if s then
					local b = bounds(s)
					if b.minY < sb.maxY - 0.1 and b.maxY > sb.maxY - 0.1 and touches(sb, b, 0) then entered = true end
				end
			end
			check(id .. ": shaft enters the socket", entered)
			-- grip at the opposite (-Y) end, working end at +Y
			local gripOk, endOk = false, false
			for _, name in ipairs(c.Grip) do
				local g = byName(parts, name)
				if g and bounds(g).c.Y < sb.c.Y - 1 and bounds(g).minY <= minY + 0.9 then gripOk = true end
			end
			for _, name in ipairs(c.WorkingEnd) do
				local w = byName(parts, name)
				if w and bounds(w).c.Y > sb.c.Y + 1 and bounds(w).maxY >= maxY - 0.9 then endOk = true end
			end
			check(id .. ": grip at the opposite end (-Y)", gripOk)
			check(id .. ": working end at +Y", endOk)
		end
	end
end

-- 3: first-person clearance ---------------------------------------------------------------------------------------
local FOV_TAN = math.tan(math.rad(35)) -- 70 degree vertical FOV
local H = 1080
local ZONE_RADIUS_PX = 60 -- crosshair + the mining face right around it

local function corners(p, scale)
	local out = {}
	for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
		out[#out + 1] = (p.Offset * Vector3.new(sx * p.Size.X / 2, sy * p.Size.Y / 2, sz * p.Size.Z / 2)) * scale -- scale the WHOLE part (position and size), like Kit.Transform
	end end end
	return out
end

-- returns (intersectsZone, anyBehindNear, bboxCentreX, bboxCentreY) for a part placed by `place` (CFrame)
local function projectPart(p, scale, place, aspect)
	local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
	local behind = false
	for _, c in ipairs(corners(p, scale)) do
		local v = place * c
		if v.Z > -0.1 then
			behind = true
		else
			local px = (v.X / -v.Z) / (FOV_TAN * aspect) * (H * aspect / 2)
			local py = (v.Y / -v.Z) / FOV_TAN * (H / 2)
			minx, maxx, miny, maxy = math.min(minx, px), math.max(maxx, px), math.min(miny, py), math.max(maxy, py)
		end
	end
	if behind then return false, true, 0, 0 end
	-- rectangle vs circle(0,0,R)
	local nx = math.max(minx, math.min(0, maxx))
	local ny = math.max(miny, math.min(0, maxy))
	local hit = (nx * nx + ny * ny) < ZONE_RADIUS_PX * ZONE_RADIUS_PX
	return hit, false, (minx + maxx) / 2, (miny + maxy) / 2
end

local aspects = { 16 / 9, 21 / 9, 4 / 3 }
local rest = ViewmodelMath.Rest()
for _, id in ipairs(appearanceIds) do
	local spec = ToolModels.GetSpec(id)
	for _, aspect in ipairs(aspects) do
		local blocked, worstT, worstPart = false, nil, nil
		for step = 0, 20 do
			local t = step / 20
			local place = ViewmodelMath.Swing(t) * rest
			for i = 2, #spec.Parts do
				local part = spec.Parts[i]
				local hit = projectPart(part, ViewmodelMath.Scale, place, aspect)
				if hit then blocked, worstT, worstPart = true, t, part.Name end
			end
		end
		check(("%s: crosshair area clear at rest and through the swing (aspect %.2f)"):format(id, aspect), not blocked,
			blocked and ("part %s at t=%.2f"):format(worstPart, worstT) or nil)
	end
	-- lower-right at rest: average of part centres
	local sx, sy, n = 0, 0, 0
	for i = 2, #spec.Parts do
		local hit, behind, cx, cy = projectPart(spec.Parts[i], ViewmodelMath.Scale, rest, 16 / 9)
		if not behind then sx, sy, n = sx + cx, sy + cy, n + 1 end
	end
	check(id .. ": sits in the lower right at rest", n > 0 and sx / n > 0 and sy / n < 0, ("avg px (%.0f, %.0f)"):format(sx / math.max(n, 1), sy / math.max(n, 1)))
end

-- carried artifacts: low and central, view above and around stays clear
for id, def in pairs(Defs.Treasure) do
	if def.RequiresCarry or def.Model then
		local specs = TreasureModels.Specs(id, def)
		for _, aspect in ipairs(aspects) do
			local blocked = false
			for _, part in ipairs(specs) do
				local hit = projectPart(part, ViewmodelMath.ArtifactScale, ViewmodelMath.ArtifactRest, aspect)
				if hit then blocked = true end
			end
			check(("carried %s: crosshair area clear (aspect %.2f)"):format(id, aspect), not blocked)
		end
	end
end

print(("tool assembly tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
